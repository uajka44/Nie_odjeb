//+------------------------------------------------------------------+
//|                                            DatabaseManager.mqh |
//|                  Zarządzanie bazą danych dla EA Nie_odjeb        |
//|                  ROZSZERZONA WERSJA z pozycjami                  |
//+------------------------------------------------------------------+

#ifndef DATABASEMANAGER_MQH
#define DATABASEMANAGER_MQH

#include "Config.mqh"
#include <Trade\DealInfo.mqh>

// Zmienne globalne dla bazy danych
int g_db_handle = INVALID_HANDLE;
bool g_databaseReady = false;
string g_symbolArray[];

// Nowe zmienne dla pozycji
struct PositionSLInfo 
{
    long ticket;
    double initial_sl;
    datetime time;
};

PositionSLInfo g_pending_positions[]; // Tablica do śledzenia SL pozycji limit

//+------------------------------------------------------------------+
//| Funkcje pomocnicze dla pozycji                                   |
//+------------------------------------------------------------------+
void DatabaseManager_PrintDebug(string message)
{
    Print("[DatabaseManager] ", message);
}

void DatabaseManager_LogError(string message, string function)
{
    Print("[ERROR][DatabaseManager][", function, "] ", message);
}

string DatabaseManager_TimeElapsedToString(const datetime seconds)
{
    const long days = seconds / 86400;
    return((days ? (string)days + "d " : "") + TimeToString(seconds, TIME_SECONDS));
}

string DatabaseManager_DealReasonToString(ENUM_DEAL_REASON deal_reason)
{
    switch(deal_reason)
    {
        case DEAL_REASON_CLIENT:   return ("client");
        case DEAL_REASON_MOBILE:   return ("mobile");
        case DEAL_REASON_WEB:      return ("web");
        case DEAL_REASON_EXPERT:   return ("expert");
        case DEAL_REASON_SL:       return ("sl");
        case DEAL_REASON_TP:       return ("tp");
        case DEAL_REASON_SO:       return ("so");
        case DEAL_REASON_ROLLOVER: return ("rollover");
        case DEAL_REASON_VMARGIN:  return ("vmargin");
        case DEAL_REASON_SPLIT:    return ("split");
        default:
            return ("unknown");
    }
}

//+------------------------------------------------------------------+
//| Zapisuje informacje o SL nowo otwartej pozycji                   |
//+------------------------------------------------------------------+
void DatabaseManager_RecordOpenedPositionSL(long positionId)
{
    if(!PositionSelectByTicket(positionId)) return;
    
    double sl = PositionGetDouble(POSITION_SL);
    if(sl == 0) return; // Brak SL
    
    // Zapisz SL dla każdej pozycji z ustawionym SL
    // (zakładamy że jeśli pozycja ma SL zaraz po otwarciu, to prawdopodobnie pochodzi z limitu)
    int size = ArraySize(g_pending_positions);
    ArrayResize(g_pending_positions, size + 1);
    g_pending_positions[size].ticket = positionId;
    g_pending_positions[size].initial_sl = sl;
    g_pending_positions[size].time = TimeCurrent();
    
    DatabaseManager_PrintDebug("Zapisano SL dla nowej pozycji " + IntegerToString(positionId) + " SL: " + DoubleToString(sl, 5));
}

//+------------------------------------------------------------------+
//| Pobiera zapisany SL dla pozycji                                  |
//+------------------------------------------------------------------+
double DatabaseManager_GetInitialSL(long ticket)
{
    for(int i = 0; i < ArraySize(g_pending_positions); i++)
    {
        if(g_pending_positions[i].ticket == ticket)
        {
            double sl = g_pending_positions[i].initial_sl;
            // Usuń wpis po użyciu (opcjonalnie, żeby nie zaśmiecać pamięci)
            for(int j = i; j < ArraySize(g_pending_positions) - 1; j++)
            {
                g_pending_positions[j] = g_pending_positions[j + 1];
            }
            ArrayResize(g_pending_positions, ArraySize(g_pending_positions) - 1);
            return sl;
        }
    }
    return 0; // Nie znaleziono
}

//+------------------------------------------------------------------+
//| Czyszczenie starych wpisów pending pozycji (>24h)                |
//+------------------------------------------------------------------+
void DatabaseManager_CleanupOldPendingPositions()
{
    datetime cutoffTime = TimeCurrent() - 86400; // 24 godziny temu
    
    for(int i = ArraySize(g_pending_positions) - 1; i >= 0; i--)
    {
        if(g_pending_positions[i].time < cutoffTime)
        {
            // Usuń stary wpis
            for(int j = i; j < ArraySize(g_pending_positions) - 1; j++)
            {
                g_pending_positions[j] = g_pending_positions[j + 1];
            }
            ArrayResize(g_pending_positions, ArraySize(g_pending_positions) - 1);
        }
    }
}

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
    
    // Tworzenie tabel dla świeczek
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

    // NOWA TABELA DLA POZYCJI
    string createPositionsSQL = "CREATE TABLE IF NOT EXISTS positions ("
                              "position_id INTEGER PRIMARY KEY,"
                              "open_time INTEGER,"
                              "close_time INTEGER,"
                              "ticket INTEGER,"
                              "type TEXT,"
                              "symbol TEXT,"
                              "volume REAL,"
                              "open_price REAL,"
                              "close_price REAL,"
                              "sl REAL,"
                              "tp REAL,"
                              "commission REAL,"
                              "swap REAL,"
                              "profit REAL,"
                              "profit_points INTEGER,"
                              "balance REAL,"
                              "magic_number INTEGER,"
                              "duration TEXT,"
                              "open_reason TEXT,"
                              "close_reason TEXT,"
                              "open_comment TEXT,"
                              "close_comment TEXT,"
                              "deal_in_ticket TEXT,"
                              "deal_out_tickets TEXT,"
                              "sl_recznie REAL"  // NOWA KOLUMNA dla SL z limitów
                              ")";
    
    if(!DatabaseExecute(g_db_handle, createPositionsSQL))
    {
        DatabaseManager_LogError("Błąd tworzenia tabeli positions: " + IntegerToString(GetLastError()), "DatabaseManager_Init");
        return false;
    }

    DatabaseManager_PrintDebug("✓ Tabela positions utworzona/sprawdzona");

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

//+------------------------------------------------------------------+
//| NOWA FUNKCJA: Pobiera ostatnią datę pozycji z bazy               |
//+------------------------------------------------------------------+
datetime DatabaseManager_GetLastPositionDate()
{
    if(!g_databaseReady || g_db_handle == INVALID_HANDLE)
    {
        return D'2020.01.01'; // Domyślna data rozpoczęcia
    }
    
    int request = DatabasePrepare(g_db_handle, "SELECT MAX(close_time) FROM positions");
    datetime lastDate = D'2020.01.01';
    
    if(request != INVALID_HANDLE)
    {
        if(DatabaseRead(request))
        {
            long columnValue;
            if(DatabaseColumnLong(request, 0, columnValue) && columnValue > 0)
            {
                lastDate = (datetime)columnValue;
            }
        }
        DatabaseFinalize(request);
    }
    
    return lastDate;
}

//+------------------------------------------------------------------+
//| NOWA FUNKCJA: Sprawdza i zapisuje brakujące pozycje              |
//+------------------------------------------------------------------+
bool DatabaseManager_SaveMissingPositions()
{
    if(!g_databaseReady)
    {
        DatabaseManager_LogError("Baza nie jest gotowa", "DatabaseManager_SaveMissingPositions");
        return false;
    }
    
    // Sprawdź typ rachunku
    if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
    {
        DatabaseManager_LogError("EA wymaga rachunku hedging", "DatabaseManager_SaveMissingPositions");
        return false;
    }
    
    // Pobierz ostatnią datę z bazy danych
    datetime fromDate = DatabaseManager_GetLastPositionDate();
    datetime toDate = TimeCurrent();
    
    DatabaseManager_PrintDebug("Sprawdzam pozycje od: " + TimeToString(fromDate) + " do: " + TimeToString(toDate));
    
    // Jeśli ostatnia pozycja była niedawno (mniej niż 5 minut temu), nie ma potrzeby sprawdzać
    if(toDate - fromDate < 300)
    {
        DatabaseManager_PrintDebug("Ostatnia pozycja była niedawno - pomijam sprawdzenie");
        return true;
    }
    
    // Wybierz historię
    if(!HistorySelect(fromDate, toDate))
    {
        DatabaseManager_LogError("HistorySelect failed", "DatabaseManager_SaveMissingPositions");
        return false;
    }
    
    int dealsTotal = HistoryDealsTotal();
    DatabaseManager_PrintDebug("Transakcji w sprawdzanym okresie: " + IntegerToString(dealsTotal));
    
    if(dealsTotal == 0)
    {
        DatabaseManager_PrintDebug("Brak nowych transakcji");
        return true;
    }
    
    // Zbierz unikalne ID pozycji
    long positionIds[];
    CDealInfo deal;
    
    for(int i = 0; i < dealsTotal; i++)
    {
        if(!deal.SelectByIndex(i)) continue;
        if(deal.Entry() != DEAL_ENTRY_OUT && deal.Entry() != DEAL_ENTRY_OUT_BY) continue; // Tylko zamknięte pozycje
        if(deal.DealType() != DEAL_TYPE_BUY && deal.DealType() != DEAL_TYPE_SELL) continue;
        
        long posId = deal.PositionId();
        
        // Sprawdź czy już dodane do listy
        bool exists = false;
        for(int j = 0; j < ArraySize(positionIds); j++)
        {
            if(positionIds[j] == posId)
            {
                exists = true;
                break;
            }
        }
        
        if(!exists)
        {
            int size = ArraySize(positionIds);
            ArrayResize(positionIds, size + 1);
            positionIds[size] = posId;
        }
    }
    
    int totalPos = ArraySize(positionIds);
    DatabaseManager_PrintDebug("Znalezionych pozycji do sprawdzenia: " + IntegerToString(totalPos));
    
    if(totalPos == 0)
    {
        DatabaseManager_PrintDebug("Brak pozycji do sprawdzenia");
        return true;
    }
    
    int saved = 0;
    
    // Sprawdź każdą pozycję pojedynczo
    for(int i = 0; i < totalPos && !IsStopped(); i++)
    {
        if(DatabaseManager_ProcessSinglePosition(positionIds[i]))
        {
            saved++;
        }
        
        // Co 5 pozycji krótka przerwa dla wydajności
        if(i % 5 == 0) Sleep(1);
    }
    
    if(saved > 0)
    {
        DatabaseManager_PrintDebug("✓ Zapisano " + IntegerToString(saved) + " nowych pozycji do bazy");
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| NOWA FUNKCJA: Przetwarza pojedynczą pozycję                      |
//+------------------------------------------------------------------+
bool DatabaseManager_ProcessSinglePosition(long positionId)
{
    // Sprawdź czy pozycja już istnieje w bazie
    int checkRequest = DatabasePrepare(g_db_handle, StringFormat("SELECT COUNT(*) FROM positions WHERE position_id = %d", positionId));
    if(checkRequest != INVALID_HANDLE)
    {
        if(DatabaseRead(checkRequest))
        {
            long count;
            if(DatabaseColumnLong(checkRequest, 0, count) && count > 0)
            {
                DatabaseFinalize(checkRequest);
                return false; // Pozycja już istnieje
            }
        }
        DatabaseFinalize(checkRequest);
    }
    
    if(!HistorySelectByPosition(positionId))
    {
        return false;
    }
    
    int deals = HistoryDealsTotal();
    if(deals < 2) return false; // Musi mieć open i close
    
    CDealInfo deal;
    
    // Zmienne dla danych pozycji
    string symbol = "", open_comment = "", close_comment = "", deal_in_ticket = "", deal_out_ticket = "";
    long type = -1, magic = 0, open_reason = -1, close_reason = -1;
    double volume = 0, open_price = 0, close_price = 0, profit = 0;
    double commission = 0, swap = 0, sl = 0, tp = 0, sl_recznie = 0;
    datetime open_time = 0, close_time = 0;
    bool hasOpen = false, hasClose = false;
    
    // Statyczna zmienna dla akumulacji balance
    static double running_balance = 0;
    
    // Zbieranie danych z wszystkich transakcji pozycji
    for(int i = 0; i < deals; i++)
    {
        if(!deal.SelectByIndex(i)) continue;
        
        // Akumuluj commission, swap i profit
        commission += deal.Commission();
        swap += deal.Swap();
        profit += deal.Profit();
        
        if(deal.Entry() == DEAL_ENTRY_IN)
        {
            hasOpen = true;
            symbol = deal.Symbol();
            type = deal.DealType();
            volume = deal.Volume();
            open_price = deal.Price();
            open_time = deal.Time();
            magic = deal.Magic();
            open_comment = deal.Comment();
            deal_in_ticket = IntegerToString(deal.Ticket());
            open_reason = HistoryDealGetInteger(deal.Ticket(), DEAL_REASON);
            
            // SPRAWDŹ CZY TO BYŁA POZYCJA Z LIMITU - pobierz zapisany SL
            sl_recznie = DatabaseManager_GetInitialSL(deal.Ticket());
        }
        else if(deal.Entry() == DEAL_ENTRY_OUT || deal.Entry() == DEAL_ENTRY_OUT_BY)
        {
            hasClose = true;
            close_price = deal.Price();
            close_time = deal.Time();
            close_comment = deal.Comment();
            deal_out_ticket = IntegerToString(deal.Ticket());
            close_reason = HistoryDealGetInteger(deal.Ticket(), DEAL_REASON);
            
            // Próbuj pobrać SL i TP
            sl = HistoryDealGetDouble(deal.Ticket(), DEAL_SL);
            tp = HistoryDealGetDouble(deal.Ticket(), DEAL_TP);
        }
    }
    
    // Sprawdź kompletność danych
    if(!hasOpen || !hasClose || open_time == 0 || close_time == 0)
    {
        return false; // Pozycja niekompletna
    }
    
    // Oblicz punkty
    int points = 0;
    if(symbol != "")
    {
        SymbolSelect(symbol, true);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point > 0)
        {
            points = (int)MathRound((type == DEAL_TYPE_BUY ? close_price - open_price : open_price - close_price) / point);
        }
    }
    
    string duration = DatabaseManager_TimeElapsedToString(close_time - open_time);
    
    // Aktualizuj running balance
    running_balance += profit + swap + commission;
    
    // Konwertuj powody na stringi
    string open_reason_str = DatabaseManager_DealReasonToString((ENUM_DEAL_REASON)open_reason);
    string close_reason_str = DatabaseManager_DealReasonToString((ENUM_DEAL_REASON)close_reason);
    
    // Zapis do bazy danych z nową kolumną sl_recznie
    string insertSQL = StringFormat(
        "INSERT OR IGNORE INTO positions "
        "(position_id, open_time, close_time, ticket, type, symbol, volume, open_price, close_price, "
        "sl, tp, commission, swap, profit, profit_points, balance, magic_number, duration, "
        "open_reason, close_reason, open_comment, close_comment, deal_in_ticket, deal_out_tickets, sl_recznie) "
        "VALUES (%d, %d, %d, %d, '%s', '%s', %.2f, %.5f, %.5f, %.5f, %.5f, %.2f, %.2f, %.2f, %d, %.2f, %d, '%s', '%s', '%s', '%s', '%s', '%s', '%s', %.5f)",
        positionId,
        (long)open_time,
        (long)close_time,
        positionId, // ticket = position_id
        (type == DEAL_TYPE_BUY) ? "buy" : "sell",
        symbol,
        volume,
        open_price,
        close_price,
        sl,
        tp,
        commission,
        swap,
        profit,
        points,
        running_balance,
        magic,
        duration,
        open_reason_str,
        close_reason_str,
        open_comment,
        close_comment,
        deal_in_ticket,
        deal_out_ticket,
        sl_recznie
    );
    
    // Wykonaj SQL
    if(!DatabaseExecute(g_db_handle, insertSQL))
    {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| NOWA FUNKCJA: Obsługa zamkniętej pozycji w OnTradeTransaction    |
//+------------------------------------------------------------------+
void DatabaseManager_HandleClosedPosition()
{
    if(!g_databaseReady)
    {
        return;
    }
    
    // Sprawdź czy nie pominęliśmy jakiejś pozycji wcześniej
    DatabaseManager_SaveMissingPositions();
    
    // Wyczyść stare wpisy pending pozycji co jakiś czas
    static datetime lastCleanup = 0;
    if(TimeCurrent() - lastCleanup > 3600) // Co godzinę
    {
        DatabaseManager_CleanupOldPendingPositions();
        lastCleanup = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| NOWA FUNKCJA: Obsługa nowo otwartej pozycji                    |
//+------------------------------------------------------------------+
void DatabaseManager_HandleOpenedPosition(long positionId)
{
    // Zapisz SL jeśli pozycja ma ustawiony od razu (prawdopodobnie z limitu)
    DatabaseManager_RecordOpenedPositionSL(positionId);
}

//+------------------------------------------------------------------+
//| NOWA FUNKCJA: Statystyki bazy danych                             |
//+------------------------------------------------------------------+
void DatabaseManager_PrintStats()
{
    if(!g_databaseReady) 
    {
        DatabaseManager_PrintDebug("Baza danych nie jest gotowa");
        return;
    }
    
    int request = DatabasePrepare(g_db_handle, "SELECT COUNT(*) FROM positions");
    if(request != INVALID_HANDLE)
    {
        if(DatabaseRead(request))
        {
            long count;
            if(DatabaseColumnLong(request, 0, count))
            {
                DatabaseManager_PrintDebug("Pozycji w bazie: " + IntegerToString(count));
            }
        }
        DatabaseFinalize(request);
    }
    
    // Pokaż ostatnie 3 pozycje
    int dataReq = DatabasePrepare(g_db_handle, 
        "SELECT position_id, symbol, type, profit, sl_recznie FROM positions ORDER BY close_time DESC LIMIT 3");
    
    if(dataReq != INVALID_HANDLE)
    {
        DatabaseManager_PrintDebug("=== OSTATNIE 3 POZYCJE ===");
        while(DatabaseRead(dataReq))
        {
            long id;
            string symbol, type;
            double profit, sl_recznie;
            
            DatabaseColumnLong(dataReq, 0, id);
            DatabaseColumnText(dataReq, 1, symbol);
            DatabaseColumnText(dataReq, 2, type);
            DatabaseColumnDouble(dataReq, 3, profit);
            DatabaseColumnDouble(dataReq, 4, sl_recznie);
            
            string sl_info = (sl_recznie > 0) ? " [SL z limitu: " + DoubleToString(sl_recznie, 5) + "]" : "";
            DatabaseManager_PrintDebug("ID:" + IntegerToString(id) + " " + symbol + " " + type + " Profit:" + DoubleToString(profit, 2) + sl_info);
        }
        DatabaseFinalize(dataReq);
    }
}

#endif // DATABASEMANAGER_MQH