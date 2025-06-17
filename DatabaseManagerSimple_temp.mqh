//+------------------------------------------------------------------+
//|                                DatabaseManagerSimple.mqh        |
//|                      UPROSZCZONA WERSJA - BEZ TRANSAKCJI        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property strict

#include <Trade\DealInfo.mqh>
#include "Utils.mqh"
#include "ConfigManager.mqh"

//+------------------------------------------------------------------+
//| UPROSZCZONA KLASA DatabaseManager                               |
//+------------------------------------------------------------------+
class CDatabaseManager
{
private:
    int m_db_handle;
    bool m_initialized;
    bool m_database_ready;
    string m_db_path;
    
public:
    CDatabaseManager() : m_db_handle(INVALID_HANDLE), m_initialized(false), m_database_ready(false) {}
    ~CDatabaseManager() { Cleanup(); }
    
    //+------------------------------------------------------------------+
    //| Inicjalizacja                                                   |
    //+------------------------------------------------------------------+
    bool Initialize()
    {
        if(m_initialized) return true;
        
        m_db_path = "multi_candles.db";
        
        // Próba otwarcia bazy w katalogu MQL5\Files (bez DATABASE_OPEN_COMMON)
        m_db_handle = DatabaseOpen(m_db_path, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE);
        
        if(m_db_handle == INVALID_HANDLE)
        {
            PrintDebug("Próba otwarcia bazy w katalogu Common...");
            // Fallback - próba z COMMON
            m_db_handle = DatabaseOpen(m_db_path, DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE | DATABASE_OPEN_COMMON);
        }
        
        if(m_db_handle == INVALID_HANDLE)
        {
            LogError("Nie można otworzyć bazy danych: " + IntegerToString(GetLastError()), "Initialize");
            return false;
        }
        
        // Wyświetl rzeczywistą ścieżkę
        PrintDebug("✓ Baza danych otwarta: " + m_db_path + " (handle: " + IntegerToString(m_db_handle) + ")");
        PrintDebug("Lokalizacja: C:\\Users\\anasy\\AppData\\Roaming\\MetaQuotes\\Terminal\\7B8FFB3E490B2B8923BCC10180ACB2DC\\MQL5\\Files\\");
        
        if(!CreateTables())
        {
            LogError("Błąd przy tworzeniu tabel", "Initialize");
            return false;
        }
        
        m_database_ready = true;
        m_initialized = true;
        PrintDebug("✓ DatabaseManager zainicjalizowany");
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Utworzenie tabeli z dodatkowymi polami                          |
    //+------------------------------------------------------------------+
    bool CreateTables()
    {
        string createSQL = "CREATE TABLE IF NOT EXISTS positions ("
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
                          "deal_out_tickets TEXT"
                          ")";
        
        if(!DatabaseExecute(m_db_handle, createSQL))
        {
            LogError("Błąd tworzenia tabeli: " + IntegerToString(GetLastError()), "CreateTables");
            return false;
        }
        
        PrintDebug("✓ Tabela positions gotowa");
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| SUPER PROSTA WERSJA eksportu - BEZ TRANSAKCJI                   |
    //+------------------------------------------------------------------+
    bool ExportHistoryPositionsToSQLite()
    {
        if(!m_database_ready)
        {
            LogError("Baza nie jest gotowa", "ExportHistoryPositionsToSQLite");
            return false;
        }
        
        PrintDebug("=== PROSTY EKSPORT POZYCJI ===");
        
        // Sprawdź typ rachunku
        if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
        {
            LogError("EA wymaga rachunku hedging", "ExportHistoryPositionsToSQLite");
            return false;
        }
        
        datetime fromDate = Config.GetStartDate();
        datetime toDate = TimeCurrent();
        
        PrintDebug("Eksport od: " + TimeToString(fromDate) + " do: " + TimeToString(toDate));
        
        // Wybierz historię
        if(!HistorySelect(fromDate, toDate))
        {
            LogError("HistorySelect failed", "ExportHistoryPositionsToSQLite");
            return false;
        }
        
        int dealsTotal = HistoryDealsTotal();
        PrintDebug("Transakcji w historii: " + IntegerToString(dealsTotal));
        
        if(dealsTotal == 0)
        {
            PrintDebug("Brak transakcji do eksportu");
            return true;
        }
        
        // Zbierz pozycje wejściowe
        long positionIds[];
        CDealInfo deal;
        
        for(int i = 0; i < dealsTotal; i++)
        {
            if(!deal.SelectByIndex(i)) continue;
            if(deal.Entry() != DEAL_ENTRY_IN) continue;
            if(deal.DealType() != DEAL_TYPE_BUY && deal.DealType() != DEAL_TYPE_SELL) continue;
            
            long posId = deal.PositionId();
            
            // Sprawdź czy już dodane
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
        PrintDebug("Pozycji do przetworzenia: " + IntegerToString(totalPos));
        
        int saved = 0;
        int errors = 0;
        
        // Przetwórz każdą pozycję POJEDYNCZO
        for(int i = 0; i < totalPos && !IsStopped(); i++)
        {
            if(i % 10 == 0) // Co 10 pozycji
            {
                PrintDebug("Postęp: " + IntegerToString(i+1) + "/" + IntegerToString(totalPos));
            }
            
            if(ProcessSinglePositionSimple(positionIds[i]))
            {
                saved++;
            }
            else
            {
                errors++;
                if(errors > 20) // Maksymalnie 20 błędów
                {
                    LogError("Zbyt dużo błędów (" + IntegerToString(errors) + ") - kończymy", "ExportHistoryPositionsToSQLite");
                    break;
                }
            }
            
            // Bardzo krótka przerwa
            if(i % 5 == 0) Sleep(1);
        }
        
        PrintDebug("=== WYNIKI EKSPORTU ===");
        PrintDebug("✓ Zapisano: " + IntegerToString(saved) + " pozycji");
        PrintDebug("✗ Błędy: " + IntegerToString(errors) + " pozycji");
        
        return (saved > 0);
    }
    
    //+------------------------------------------------------------------+
    //| Przetwarza jedną pozycję - ROZSZERZONE o nowe pola            |
    //+------------------------------------------------------------------+
    bool ProcessSinglePositionSimple(long positionId)
    {
        if(!HistorySelectByPosition(positionId))
        {
            return false;
        }
        
        int deals = HistoryDealsTotal();
        if(deals < 2) return false; // Musi mieć open i close
        
        CDealInfo deal;
        
        // Dane pozycji - WSZYSTKIE POLA
        string symbol = "", open_comment = "", close_comment = "", deal_in_ticket = "", deal_out_ticket = "";
        long type = -1, magic = 0, open_reason = -1, close_reason = -1;
        double volume = 0, open_price = 0, close_price = 0, profit = 0;
        double commission = 0, swap = 0, sl = 0, tp = 0;
        datetime open_time = 0, close_time = 0;
        bool hasOpen = false, hasClose = false;
        
        // STATYCZNA ZMIENNA do akumulacji balance (jak w oryginalnym kodzie)
        static double running_balance = 0;
        
        // Znajdź open i close - ZBIERAJ WSZYSTKIE DANE
        for(int i = 0; i < deals; i++)
        {
            if(!deal.SelectByIndex(i)) continue;
            
            // Zbieraj commission i swap z każdej transakcji
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
            }
            else if(deal.Entry() == DEAL_ENTRY_OUT || deal.Entry() == DEAL_ENTRY_OUT_BY)
            {
                hasClose = true;
                close_price = deal.Price();
                close_time = deal.Time();
                close_comment = deal.Comment();
                deal_out_ticket = IntegerToString(deal.Ticket());
                close_reason = HistoryDealGetInteger(deal.Ticket(), DEAL_REASON);
                // Pobierz aktualny balance konta
                balance = AccountInfoDouble(ACCOUNT_BALANCE);
                // Próbuj pobrać SL i TP z transakcji zamykającej
                sl = HistoryDealGetDouble(deal.Ticket(), DEAL_SL);
                tp = HistoryDealGetDouble(deal.Ticket(), DEAL_TP);
            }
        }
        
        // Sprawdź kompletność
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
        
        string duration = TimeElapsedToString(close_time - open_time);
        
        // Akumuluj balance (jak w oryginalnym kodzie)
        running_balance += profit + swap + commission;
        
        // Konwertuj powody na stringi
        string open_reason_str = DealReasonToString((ENUM_DEAL_REASON)open_reason);
        string close_reason_str = DealReasonToString((ENUM_DEAL_REASON)close_reason);
        
        // BEZPOŚREDNIE WYKONANIE SQL - WSZYSTKIE POLA
        string directSQL = StringFormat(
            "INSERT OR IGNORE INTO positions "
            "(position_id, open_time, close_time, ticket, type, symbol, volume, open_price, close_price, "
            "sl, tp, commission, swap, profit, profit_points, balance, magic_number, duration, "
            "open_reason, close_reason, open_comment, close_comment, deal_in_ticket, deal_out_tickets) "
            "VALUES (%d, %d, %d, %d, '%s', '%s', %.2f, %.5f, %.5f, %.5f, %.5f, %.2f, %.2f, %.2f, %d, %.2f, %d, '%s', '%s', '%s', '%s', '%s', '%s', '%s')",
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
            deal_out_ticket
        );
        
        // Wykonaj bezpośrednio SQL
        if(!DatabaseExecute(m_db_handle, directSQL))
        {
            // Nie logujemy błędów - zbyt dużo spamu
            return false;
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Funkcje pomocnicze                                              |
    //+------------------------------------------------------------------+
    bool IsDatabaseReady() { return m_database_ready; }
    
    void PrintDatabaseStats()
    {
        if(!m_database_ready) return;
        
        int request = DatabasePrepare(m_db_handle, "SELECT COUNT(*) FROM positions");
        if(request != INVALID_HANDLE)
        {
            if(DatabaseRead(request))
            {
                long count;
                if(DatabaseColumnLong(request, 0, count))
                {
                    PrintDebug("Pozycji w bazie: " + IntegerToString(count));
                }
            }
            DatabaseFinalize(request);
        }
    }
    
    bool TestReadLastPositions()
    {
        PrintDebug("=== TEST ODCZYTU ===");
        
        if(!m_database_ready)
        {
            LogError("Baza nie gotowa", "TestReadLastPositions");
            return false;
        }
        
        // Sprawdź liczbę
        int countReq = DatabasePrepare(m_db_handle, "SELECT COUNT(*) FROM positions");
        long total = 0;
        
        if(countReq != INVALID_HANDLE)
        {
            if(DatabaseRead(countReq))
            {
                DatabaseColumnLong(countReq, 0, total);
            }
            DatabaseFinalize(countReq);
        }
        
        PrintDebug("Łącznie pozycji: " + IntegerToString(total));
        
        if(total == 0)
        {
            PrintDebug("Baza pusta");
            return true;
        }
        
        // Ostatnie 3 - ROZSZERZONE
        int dataReq = DatabasePrepare(m_db_handle, 
            "SELECT position_id, ticket, symbol, type, volume, sl, tp, commission, swap, profit, profit_points "
            "FROM positions ORDER BY close_time DESC LIMIT 3");
        
        if(dataReq == INVALID_HANDLE)
        {
            LogError("Błąd zapytania", "TestReadLastPositions");
            return false;
        }
        
        int count = 0;
        while(DatabaseRead(dataReq))
        {
            count++;
            long id, ticket, points;
            string symbol, type;
            double volume, sl, tp, commission, swap, profit;
            
            DatabaseColumnLong(dataReq, 0, id);
            DatabaseColumnLong(dataReq, 1, ticket);
            DatabaseColumnText(dataReq, 2, symbol);
            DatabaseColumnText(dataReq, 3, type);
            DatabaseColumnDouble(dataReq, 4, volume);
            DatabaseColumnDouble(dataReq, 5, sl);
            DatabaseColumnDouble(dataReq, 6, tp);
            DatabaseColumnDouble(dataReq, 7, commission);
            DatabaseColumnDouble(dataReq, 8, swap);
            DatabaseColumnDouble(dataReq, 9, profit);
            DatabaseColumnLong(dataReq, 10, points);
            
            PrintDebug("=== POZYCJA " + IntegerToString(count) + " ===");
            PrintDebug("ID: " + IntegerToString(id) + " | Ticket: " + IntegerToString(ticket));
            PrintDebug("Symbol: " + symbol + " " + type + " " + DoubleToString(volume,2));
            PrintDebug("SL: " + DoubleToString(sl,5) + " | TP: " + DoubleToString(tp,5));
            PrintDebug("Commission: " + DoubleToString(commission,2) + " | Swap: " + DoubleToString(swap,2));
            PrintDebug("Profit: " + DoubleToString(profit,2) + " (" + IntegerToString(points) + "pkt)");
            PrintDebug("");
        }
        
        DatabaseFinalize(dataReq);
        PrintDebug("✓ Odczytano " + IntegerToString(count) + " pozycji");
        return true;
    }
    
    bool TestDatabaseStatus()
    {
        PrintDebug("=== STATUS BAZY DANYCH ===");
        PrintDebug("Ścieżka: " + m_db_path);
        PrintDebug("Handle: " + IntegerToString(m_db_handle));
        PrintDebug("Gotowa: " + BoolToString(m_database_ready));
        
        // Pokaż prawdopodobną lokalizację pliku
        PrintDebug("Prawdopodobna lokalizacja:");
        PrintDebug("  C:\\Users\\anasy\\AppData\\Roaming\\MetaQuotes\\Terminal\\7B8FFB3E490B2B8923BCC10180ACB2DC\\MQL5\\Files\\multi_candles.db");
        PrintDebug("  (jeśli otworzona bez flagi COMMON)");
        PrintDebug("  LUB");
        PrintDebug("  C:\\Users\\anasy\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\multi_candles.db");
        PrintDebug("  (jeśli otworzona z flagą COMMON)");
        
        if(m_db_handle == INVALID_HANDLE)
        {
            LogError("Handle nieprawidłowy", "TestDatabaseStatus");
            return false;
        }
        
        // Test prostego zapytania
        if(!DatabaseExecute(m_db_handle, "SELECT 1"))
        {
            LogError("Test zapytania failed: " + IntegerToString(GetLastError()), "TestDatabaseStatus");
            return false;
        }
        
        PrintDebug("✓ Baza odpowiada na zapytania");
        return true;
    }
    
    string TimeElapsedToString(const datetime seconds)
    {
        const long days = seconds / 86400;
        return((days ? (string)days + "d " : "") + TimeToString(seconds, TIME_SECONDS));
    }
    
    //+------------------------------------------------------------------+
    //| Konwertuje DEAL_REASON na string                                |
    //+------------------------------------------------------------------+
    string DealReasonToString(ENUM_DEAL_REASON deal_reason)
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
    
    void Cleanup()
    {
        if(m_db_handle != INVALID_HANDLE)
        {
            DatabaseClose(m_db_handle);
            m_db_handle = INVALID_HANDLE;
            PrintDebug("Baza zamknięta");
        }
        m_database_ready = false;
        m_initialized = false;
    }
};

// Globalna instancja
CDatabaseManager Database;
