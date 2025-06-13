//+------------------------------------------------------------------+
//|                                            DatabaseManager.mqh |
//|                  Zarządzanie bazą danych dla EA Nie_odjeb        |
//+------------------------------------------------------------------+

#ifndef DATABASEMANAGER_MQH
#define DATABASEMANAGER_MQH

#include "Config.mqh"

// Zmienne globalne dla bazy danych
int g_db_handle = INVALID_HANDLE;
bool g_databaseReady = false;
string g_symbolArray[];

//+------------------------------------------------------------------+
//| Inicjalizacja bazy danych                                        |
//+------------------------------------------------------------------+
bool DatabaseManager_Init()
{
    string dbPath = "multi_candles.db";
    
    g_db_handle = DatabaseOpen(dbPath, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE);
    
    if(g_db_handle == INVALID_HANDLE)
    {
        Print("Błąd przy otwieraniu bazy danych: ", GetLastError());
        return false;
    }
    
    // Wyświetl faktyczną lokalizację bazy
    string terminalPath = TerminalInfoString(TERMINAL_DATA_PATH);
    string fullDbPath = terminalPath + "\\MQL5\\Files\\" + dbPath;
    Print("Baza danych otwarta pomyślnie w lokalizacji: ", fullDbPath);
    
    // Przygotuj tablicę symboli
    StringSplit(Config_GetSymbols(), ',', g_symbolArray);
    
    // Tworzenie tabel dla każdego symbolu
    for(int i = 0; i < ArraySize(g_symbolArray); i++)
    {
        string symbol = g_symbolArray[i];
        StringTrimLeft(symbol);
        StringTrimRight(symbol);

        string createTableSQL = StringFormat("CREATE TABLE IF NOT EXISTS [%s] ("
                                "time INTEGER PRIMARY KEY,"
                                "open REAL,"
                                "high REAL,"
                                "low REAL,"
                                "close REAL,"
                                "tick_volume INTEGER,"
                                "spread INTEGER,"
                                "real_volume INTEGER)", symbol);
        
        if(!DatabaseExecute(g_db_handle, createTableSQL))
        {
            Print("Błąd przy tworzeniu tabeli dla ", symbol, ": ", GetLastError());
            return false;
        }
        
        Print("Tabela utworzona/sprawdzona dla ", symbol);
    }

    g_databaseReady = true;
    Print("Baza danych zainicjalizowana pomyślnie");
    return true;
}

//+------------------------------------------------------------------+
//| Deinicjalizacja bazy danych                                      |
//+------------------------------------------------------------------+
void DatabaseManager_Deinit()
{
    if(g_db_handle != INVALID_HANDLE)
    {
        DatabaseClose(g_db_handle);
        g_db_handle = INVALID_HANDLE;
        g_databaseReady = false;
        Print("Baza danych zamknięta");
    }
}

//+------------------------------------------------------------------+
//| Zapis danych świeczki do bazy                                     |
//+------------------------------------------------------------------+
void DatabaseManager_SaveCandleData(string symbol, MqlRates &candle)  
{
    if(g_db_handle == INVALID_HANDLE || !g_databaseReady)
    {
        Print("Baza danych nie jest gotowa");
        return;
    }

    string directSQL = StringFormat(
        "INSERT OR REPLACE INTO [%s] VALUES (%d, %.5f, %.5f, %.5f, %.5f, %d, %d, %d)", 
        symbol, 
        (long)candle.time,
        candle.open,
        candle.high, 
        candle.low,
        candle.close,
        candle.tick_volume,
        candle.spread,
        candle.real_volume
    );
    
    if(!DatabaseExecute(g_db_handle, directSQL))
    {
        Print("Błąd przy zapisywaniu danych dla ", symbol, ": ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Przetwarzanie symbolu - eksport świeczek                         |
//+------------------------------------------------------------------+
void DatabaseManager_ProcessSymbol(string symbol)
{
    string querySQL = StringFormat("SELECT MAX(time) FROM [%s]", symbol);
    
    int queryRequest = DatabasePrepare(g_db_handle, querySQL);
    datetime startTime;

    if(queryRequest != INVALID_HANDLE)
    {
        if(DatabaseRead(queryRequest))
        {
            long columnValue;
            if(DatabaseColumnLong(queryRequest, 0, columnValue))
            {
                startTime = (datetime)columnValue;
                if(startTime == 0)
                {
                    startTime = Config_GetStartDate();
                }
                else
                {
                    startTime += 60;
                }
            }
            else
            {
                startTime = Config_GetStartDate();
            }
        }
        else
        {
            startTime = Config_GetStartDate();
        }
        
        DatabaseFinalize(queryRequest);
    }
    else
    {
        Print("Błąd przy pobieraniu ostatniego czasu z bazy danych dla ", symbol);
        return;
    }

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int bars = (int)((TimeCurrent() - startTime) / 60);
    int copied = CopyRates(symbol, PERIOD_M1, 1, bars, rates);
    
    if(copied > 0)
    {
        for(int i = copied - 1; i >= 0; i--)
        {
            DatabaseManager_SaveCandleData(symbol, rates[i]);
            if(i % 100 == 0 && i != 0) 
            { 
                Print("Wykonano ", i, " iteracji"); 
            }
        }

        Print("Zapisano ", copied, " nowych świeczek dla symbolu ", symbol);
    }
    else
    {
        Print("Brak nowych danych do zapisania dla symbolu ", symbol);
    }
}

//+------------------------------------------------------------------+
//| Eksport świeczek dla wszystkich symboli                          |
//+------------------------------------------------------------------+
void DatabaseManager_ExportCandles()
{
    if(!g_databaseReady || g_db_handle == INVALID_HANDLE)
    {
        Print("Baza danych nie jest gotowa lub nieprawidłowa");
        return;
    }
    
    Print("Rozpoczynam eksport świeczek...");
    
    if(!DatabaseExecute(g_db_handle, "BEGIN TRANSACTION"))
    {
        Print("Błąd przy rozpoczynaniu transakcji: ", GetLastError());
        return;
    }
    
    for(int i = 0; i < ArraySize(g_symbolArray); i++)                    
    {
        Print("Zapisujemy świeczki dla instrumentu ", g_symbolArray[i]);
        DatabaseManager_ProcessSymbol(g_symbolArray[i]);
        if(i % 100 == 0 && i != 0) 
        {
            Print("Wykonano ", i, " iteracji");
        }
    }
    
    if(!DatabaseExecute(g_db_handle, "COMMIT"))
    {
        Print("Błąd przy zatwierdzaniu transakcji: ", GetLastError());
        DatabaseExecute(g_db_handle, "ROLLBACK");
    }
    else
    {
        Print("Eksport świeczek zakończony pomyślnie");
    }
}

#endif // DATABASEMANAGER_MQH
