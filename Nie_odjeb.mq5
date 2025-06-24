//+------------------------------------------------------------------+
//|                                                     Nie_odjeb.mq5 |
//|                                  Copyright 2025, Twój Autor      |
//|                                             https://www.mql5.com |
//|                           PRZEPISANE NA NATYWNĄ OBSŁUGĘ SQLite   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Twój Autor"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Include bibliotek systemowych
#include <Trade\Trade.mqh>

// Include plików projektu
#include "Include\Config.mqh"
#include "Include\DataStructures.mqh"
#include "Include\DatabaseManager.mqh"
#include "Include\BreakManager.mqh"
#include "Include\VolumeManager.mqh"
#include "Include\PositionManager.mqh"

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{  
    Print("=== Inicjalizacja EA Nie_odjeb ===");
    
    // Inicjalizacja bazy danych
    if(!DatabaseManager_Init())
    {
        Print("BŁĄD: Nie udało się zainicjalizować bazy danych");
        return INIT_FAILED;
    }
    
    // Inicjalizacja ustawień instrumentów
    if(!Config_InitializeInstrumentSettings())
    {
        Print("BŁĄD: Nie udało się zainicjalizować ustawień instrumentów");
        return INIT_FAILED;
    }
    
    // Inicjalizacja zarządzania przerwami
    BreakManager_Init();
    
    // Inicjalizacja zarządzania pozycjami
    PositionManager_Init();
    
    // Ustawienie timera
    EventSetTimer(Config_GetTimerInterval());
    
    Print("=== EA Nie_odjeb zainicjalizowany pomyślnie ===");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== Deinicjalizacja EA Nie_odjeb ===");
    
    EventKillTimer();
    DatabaseManager_Deinit();
    
    Print("EA Nie_odjeb zatrzymany. Powód: ", reason);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Sprawdzenie pozycji pod kątem maksymalnej straty
    PositionManager_CheckAllPositionsForMaxLoss();
    
    // Monitoring przerwy (działa tylko podczas przerwy)
    BreakManager_MonitorAndBlockTrades();
    
    // Usunięto: CheckAndRemoveExpiredDots() - już nie potrzebne
}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    switch(id)
    {
        case CHARTEVENT_KEYDOWN:
        {
            switch((int)lparam)
            {
                case 74:   // klawisz j - eksport świeczek
                {
                    DatabaseManager_ExportCandles();
                    break;
                }
                case 80:   // klawisz p - statystyki pozycji (P jak positions)
                {
                    DatabaseManager_PrintStats();
                    break;
                }
                case 77:   // klawisz m - sprawdź brakujące pozycje (M jak missing)
                {
                    Print("=== RĘCZNE SPRAWDZENIE BRAKUJĄCYCH POZYCJI ===");
                    DatabaseManager_SaveMissingPositions();
                    DatabaseManager_PrintStats();
                    break;
                }
                case 71:   // klawisz g - pokaż edytowaną pozycję na wykresie (G jak goto)
                {
                    ShowEditedPositionOnChart();
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
    // NAJPIERW: Sprawdzenie czy nowa transakcja narusza przerwę
    BreakManager_CheckNewTransaction(trans);
    
    // Obsługa zamknięcia pozycji - zarządzanie przerwami I ZAPIS DO BAZY
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        ulong dealTicket = trans.deal;
        if(dealTicket > 0 && HistoryDealSelect(dealTicket))
        {
            long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            
            if(dealEntry == DEAL_ENTRY_OUT)
            {
                Print("OnTradeTransaction: Wykryto zamkniętą transakcję - zapisuję do bazy");
                
                // NOWA FUNKCJONALNOŚĆ: Zapisz pozycję do bazy danych
                DatabaseManager_HandleClosedPosition();
                
                // Istniejąca funkcjonalność: zarządzanie przerwami
                BreakManager_HandleClosedPosition();
            }
            else if(dealEntry == DEAL_ENTRY_IN)
            {
                Print("OnTradeTransaction: Wykryto otwarcie pozycji - sprawdzam SL");
                
                // NOWA FUNKCJONALNOŚĆ: Zapisz SL z nowo otwartej pozycji (jeśli z limitu)
                long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
                DatabaseManager_HandleOpenedPosition(positionId);
            }
        }
    }
    
    // Obsługa zmian w zleceniach i pozycjach - zarządzanie wolumenem
    Print("Transaction type: ", EnumToString(trans.type));    
    
    switch(trans.type)
    {
        case TRADE_TRANSACTION_ORDER_ADD:
            Print("Nowe zlecenie: ", trans.order);
            VolumeManager_CheckOrderStopLoss(trans.order);
            break;
            
        case TRADE_TRANSACTION_ORDER_UPDATE:
            Print("Modyfikacja zlecenia: ", trans.order);
            VolumeManager_CheckOrderStopLoss(trans.order);
            if(Config_GetChangeVolume()) 
                VolumeManager_AdjustVolToSL();
            break;
            
        case TRADE_TRANSACTION_POSITION:
            Print("Modyfikacja pozycji: ", trans.position);
            PositionManager_CheckPositionStopLoss(trans.position);
            break;
            
        case TRADE_TRANSACTION_DEAL_ADD:
            if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
            {
                Print("Nowa transakcja (potencjalnie nowa pozycja)");
                PositionManager_CheckAllPositions();
            }
            break;
    }
}

//+------------------------------------------------------------------+
//| Pokaż edytowaną pozycję na wykresie (klawisz G) - POPRAWIONA       |
//+------------------------------------------------------------------+
void ShowEditedPositionOnChart()
{
    Print("=== SZUKANIE EDYTOWANEJ POZYCJI (BAZA DANYCH) ===\n");
    
    // Odczytaj aktualnie edytowany ticket z bazy danych
    long ticket = ReadCurrentEditTicketFromDatabase();
    
    if(ticket <= 0)
    {
        Print("[G] 🔴 Brak aktywnej edycji w dzienniku Python");
        return;
    }
    
    Print("[G] 🟢 Edytowana pozycja: Ticket ", ticket);
    
    // Sprawdź czy to otwarta pozycja
    if(PositionSelectByTicket(ticket))
    {
        string symbol = PositionGetString(POSITION_SYMBOL);
        double volume = PositionGetDouble(POSITION_VOLUME);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        double profit = PositionGetDouble(POSITION_PROFIT);
        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        Print("[G] ✅ POZYCJA OTWARTA:");
        Print("[G] Symbol: ", symbol);
        Print("[G] Typ: ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"));
        Print("[G] Volume: ", volume);
        Print("[G] Cena otwarcia: ", DoubleToString(openPrice, _Digits));
        Print("[G] Cena aktualna: ", DoubleToString(currentPrice, _Digits));
        Print("[G] SL: ", (sl > 0 ? DoubleToString(sl, _Digits) : "BRAK"));
        Print("[G] TP: ", (tp > 0 ? DoubleToString(tp, _Digits) : "BRAK"));
        Print("[G] Profit: ", DoubleToString(profit, 2));
        Print("[G] Czas otwarcia: ", TimeToString(openTime));
        
        // Przejdź do wykresu symbolu i przesuń do czasu otwarcia
        SwitchToSymbolChartAndNavigate(symbol, ticket, openTime);
    }
    else
    {
        // Pozycja zamknięta - sprawdź historię
        Print("[G] 📚 Pozycja zamknięta - sprawdzam historię...");
        
        if(HistorySelectByPosition(ticket))
        {
            int dealsTotal = HistoryDealsTotal();
            if(dealsTotal > 0)
            {
                // Znajdź deal otwarcia (DEAL_ENTRY_IN)
                for(int i = 0; i < dealsTotal; i++)
                {
                    ulong deal_ticket = HistoryDealGetTicket(i);
                    if(deal_ticket > 0)
                    {
                        long dealEntry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                        if(dealEntry == DEAL_ENTRY_IN)
                        {
                            string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
                            double volume = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
                            double price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                            datetime time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
                            ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
                            
                            Print("[G] 📊 POZYCJA Z HISTORII:");
                            Print("[G] Symbol: ", symbol);
                            Print("[G] Typ: ", (deal_type == DEAL_TYPE_BUY ? "BUY" : "SELL"));
                            Print("[G] Volume: ", volume);
                            Print("[G] Cena otwarcia: ", DoubleToString(price, _Digits));
                            Print("[G] Czas otwarcia: ", TimeToString(time));
                            
                            // Przejdź do wykresu symbolu i przesuń do czasu otwarcia
                            SwitchToSymbolChartAndNavigate(symbol, ticket, time);
                            return;
                        }
                    }
                }
            }
        }
        
        Print("[G] ❌ Nie znaleziono pozycji w historii MT5");
        Print("[G] Może pozycja pochodzi z innego konta lub brokera");
    }
}

//+------------------------------------------------------------------+
//| Przełącz na wykres symbolu i nawiguj do czasu pozycji              |
//+------------------------------------------------------------------+
void SwitchToSymbolChartAndNavigate(string symbol, long ticket, datetime openTime)
{
    Print("[G] 📈 Przeszukuję otwarte wykresy dla symbolu: ", symbol);
    
    // Sprawdź wszystkie otwarte wykresy
    long chartId = ChartFirst();
    bool found = false;
    
    while(chartId >= 0)
    {
        string chartSymbol = ChartSymbol(chartId);
        
        if(chartSymbol == symbol)
        {
            // Znaleziono wykres - przejdź do niego
            if(ChartSetInteger(chartId, CHART_BRING_TO_TOP, true))
            {
                Print("[G] ✅ Przełączono na wykres: ", symbol, " (Ticket: ", ticket, ")");
                
                // NOWA FUNKCJONALNOŚĆ: Przesuń wykres do czasu otwarcia pozycji
                if(NavigateChartToTime(chartId, openTime))
                {
                    Print("[G] 🎯 Wykres przesunięty do czasu otwarcia: ", TimeToString(openTime));
                }
                
                // Dodaj komentarz z informacją o pozycji
                string comment = StringFormat("Edytowana pozycja:\nTicket: %d\nSymbol: %s\nCzas otwarcia: %s", 
                                             ticket, symbol, TimeToString(openTime));
                ChartSetString(chartId, CHART_COMMENT, comment);
                
                // Dodaj linię pionową na czas otwarcia (opcjonalnie)
                AddVerticalLineAtTime(chartId, openTime, ticket);
                
                // Odrysuj wykres
                ChartRedraw(chartId);
                
                found = true;
                break;
            }
        }
        
        chartId = ChartNext(chartId);
    }
    
    if(!found)
    {
        Print("[G] ⚠️ Nie znaleziono otwartego wykresu dla symbolu: ", symbol);
        Print("[G] 💡 Otwórz wykres ", symbol, " i spróbuj ponownie");
        
        // Opcjonalnie: spróbuj otworzyć nowy wykres (wymaga dodatkowych uprawnień)
        // long newChartId = ChartOpen(symbol, PERIOD_CURRENT);
        // if(newChartId > 0) NavigateChartToTime(newChartId, openTime);
    }
}

//+------------------------------------------------------------------+
//| Odczytuje aktualny ticket z bazy danych                         |
//+------------------------------------------------------------------+
long ReadCurrentEditTicketFromDatabase()
{
    // Ścieżka do bazy danych (ta sama co używa DatabaseManager)
    string database_path = "multi_candles.db";
    
    // Otwórz połączenie z bazą
    int db_handle = DatabaseOpen(database_path, DATABASE_OPEN_READONLY);
    
    if(db_handle == INVALID_HANDLE)
    {
        Print("[G] ❌ Nie można otworzyć bazy danych: ", database_path);
        Print("[G] 📁 Sprawdź czy plik multi_candles.db istnieje w katalogu Files");
        return 0;
    }
    
    // Zapytanie o aktualny ticket
    string query = "SELECT value FROM communication WHERE key = 'current_edit_ticket'";
    int request = DatabasePrepare(db_handle, query);
    
    if(request == INVALID_HANDLE)
    {
        Print("[G] ❌ Błąd przygotowania zapytania SQL");
        DatabaseClose(db_handle);
        return 0;
    }
    
    long ticket = 0;
    
    // Wykonaj zapytanie
    if(DatabaseRead(request))
    {
        string ticket_str = "";
        if(DatabaseColumnText(request, 0, ticket_str))
        {
            // Usuń białe znaki i skonwertuj
            StringTrimLeft(ticket_str);
            StringTrimRight(ticket_str);
            
            if(ticket_str == "" || ticket_str == "0")
            {
                ticket = 0;
            }
            else
            {
                ticket = StringToInteger(ticket_str);
            }
            
            Print("[G] 📆 Odczytano z bazy: ticket = ", ticket, " (string: '", ticket_str, "')");
        }
        else
        {
            Print("[G] ⚠️ Nie można odczytać wartości ticket z bazy");
        }
    }
    else
    {
        Print("[G] ⚠️ Brak danych komunikacji w bazie lub tabela nie istnieje");
        Print("[G] 📝 Upewnij się, że dziennik Python był uruchomiony (tworzy tabelę)");
    }
    
    // Aktualizuj heartbeat MQL5
    UpdateMQL5Heartbeat(db_handle);
    
    // Zamknij połączenia
    DatabaseFinalize(request);
    DatabaseClose(db_handle);
    
    return ticket;
}

//+------------------------------------------------------------------+
//| Aktualizuje heartbeat MQL5 w bazie danych                       |
//+------------------------------------------------------------------+
void UpdateMQL5Heartbeat(int db_handle)
{
    // Zapisz timestamp ostatniego odczytu przez MQL5
    datetime current_time = TimeCurrent();
    string timestamp_str = IntegerToString(current_time);
    
    string update_query = "INSERT OR REPLACE INTO communication (key, value, timestamp, created_by, description) VALUES ('mql5_last_read', '" + timestamp_str + "', datetime('now'), 'mql5', 'Ostatni odczyt przez MQL5')";
    
    if(!DatabaseExecute(db_handle, update_query))
    {
        // Nie logujemy błędu - to nie jest krytyczne
    }
}

//+------------------------------------------------------------------+
//| Nawiguj wykres do określonego czasu                               |
//+------------------------------------------------------------------+
bool NavigateChartToTime(long chartId, datetime targetTime)
{
    // Sprawdź czy czas jest w przyszłości
    datetime currentTime = TimeCurrent();
    if(targetTime > currentTime)
    {
        Print("[G] ⚠️ Czas otwarcia pozycji jest w przyszłości - używam czasu bieżącego");
        targetTime = currentTime;
    }
    
    // Pobierz informacje o wykresie
    ENUM_TIMEFRAMES period = (ENUM_TIMEFRAMES)ChartPeriod(chartId);
    int periodSeconds = PeriodSeconds(period);
    int visibleBars = (int)ChartGetInteger(chartId, CHART_VISIBLE_BARS);
    
    // Pobierz czas pierwszego widocznego bara
    datetime chartFirstTime = 0;
    int firstVisibleBar = 0;
    if(visibleBars > 0)
    {
        // Użyj iTime aby pobrać czas pierwszego widocznego bara
        string symbol = ChartSymbol(chartId);
        firstVisibleBar = (int)ChartGetInteger(chartId, CHART_FIRST_VISIBLE_BAR);
        chartFirstTime = iTime(symbol, period, firstVisibleBar);
    }
    
    Print("[G] 🔍 Nawigacja do czasu: ", TimeToString(targetTime));
    Print("[G] 📊 Pierwszy widoczny bar: ", firstVisibleBar, " czas: ", TimeToString(chartFirstTime));
    Print("[G] 📊 Timeframe: ", EnumToString(period), " (", periodSeconds, " sekund)");
    
    // Oblicz ile barów przesunąć
    int barsToShift = 0;
    if(chartFirstTime > 0)
    {
        barsToShift = (int)((currentTime - targetTime) / periodSeconds);
    }
    else
    {
        // Fallback - oblicz w przybliżeniu
        barsToShift = (int)((currentTime - targetTime) / periodSeconds);
    }
    
    Print("[G] 📐 Przesunięcie: ", barsToShift, " barów");
    
    // Metoda 1: Użyj ChartNavigate z CHART_END (najbardziej niezawodna)
    if(ChartNavigate(chartId, CHART_END, -barsToShift))
    {
        Print("[G] ✅ Nawigacja ChartNavigate(CHART_END) wykonana");
        return true;
    }
    
    // Metoda 2: Użyj ChartNavigate z CHART_BEGIN
    if(chartFirstTime > 0)
    {
        int barsFromBegin = (int)((targetTime - chartFirstTime) / periodSeconds);
        if(ChartNavigate(chartId, CHART_BEGIN, barsFromBegin))
        {
            Print("[G] ✅ Nawigacja ChartNavigate(CHART_BEGIN) wykonana");
            return true;
        }
    }
    
    // Metoda 3: Użyj ChartSetInteger z CHART_SHIFT
    if(ChartSetInteger(chartId, CHART_SHIFT, barsToShift))
    {
        Print("[G] ✅ Nawigacja ChartSetInteger wykonana, przesunięcie: ", barsToShift, " barów");
        return true;
    }
    
    // Metoda 4: Przesunięcie względne od aktualnej pozycji
    if(ChartNavigate(chartId, CHART_CURRENT_POS, -barsToShift))
    {
        Print("[G] ✅ Nawigacja ChartNavigate(CHART_CURRENT_POS) wykonana");
        return true;
    }
    
    Print("[G] ⚠️ Nie udało się automatycznie przesunąć wykresu");
    Print("[G] 💡 Użyj scrolla myszy lub klawiatury aby przejść do czasu: ", TimeToString(targetTime));
    Print("[G] 📝 Sugerowane przesunięcie: ", barsToShift, " barów w lewo");
    
    return false;
}

//+------------------------------------------------------------------+
//| Dodaj strzałkę do góry na dole wykresu w miejscu otwarcia pozycji    |
//+------------------------------------------------------------------+
void AddVerticalLineAtTime(long chartId, datetime openTime, long ticket)
{
    // NAJPIERW: Usuń wszystkie poprzednie strzałki edytowanych pozycji
    ClearAllEditedPositionArrows();
    
    string arrowName = "EditedPosition_" + IntegerToString(ticket);
    
    // Pobierz zakres cen na wykresie
    double chartHigh = ChartGetDouble(chartId, CHART_PRICE_MAX);
    double chartLow = ChartGetDouble(chartId, CHART_PRICE_MIN);
    
    // Oblicz pozycję na dole wykresu (5% od dołu)
    double arrowPrice = chartLow + (chartHigh - chartLow) * 0.05;
    
    // Stwórz strzałkę do góry
    if(ObjectCreate(chartId, arrowName, OBJ_ARROW_UP, 0, openTime, arrowPrice))
    {
        // Ustaw właściwości strzałki
        ObjectSetInteger(chartId, arrowName, OBJPROP_COLOR, clrHotPink);  // Różowy kolor
        ObjectSetInteger(chartId, arrowName, OBJPROP_WIDTH, 3);           // Grubość
        ObjectSetInteger(chartId, arrowName, OBJPROP_BACK, false);        // Na pierwszym planie
        ObjectSetInteger(chartId, arrowName, OBJPROP_ANCHOR, ANCHOR_BOTTOM); // Kotwica na dole
        
        // Dodaj opis (bez dodatkowych informacji o czasie)
        ObjectSetString(chartId, arrowName, OBJPROP_TEXT, "Pozycja " + IntegerToString(ticket));
        
        Print("[G] ⬆️ Dodano różową strzałkę do góry dla pozycji ", ticket);
        
        // Odrysuj wykres
        ChartRedraw(chartId);
    }
    else
    {
        Print("[G] ⚠️ Nie udało się dodać strzałki: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Usuń wszystkie strzałki edytowanych pozycji z wszystkich wykresów |
//+------------------------------------------------------------------+
void ClearAllEditedPositionArrows()
{
    // Przejdź przez wszystkie otwarte wykresy
    long chartId = ChartFirst();
    int totalRemoved = 0;
    
    while(chartId >= 0)
    {
        int objectsTotal = ObjectsTotal(chartId);
        
        // Sprawdź wszystkie obiekty na wykresie
        for(int i = objectsTotal - 1; i >= 0; i--)
        {
            string objectName = ObjectName(chartId, i);
            
            // Sprawdź czy to nasza strzałka edytowanej pozycji
            if(StringFind(objectName, "EditedPosition_") == 0)
            {
                ObjectDelete(chartId, objectName);
                totalRemoved++;
            }
        }
        
        // Odrysuj wykres jeśli coś usunięto
        if(totalRemoved > 0)
        {
            ChartRedraw(chartId);
        }
        
        chartId = ChartNext(chartId);
    }
    
    if(totalRemoved > 0)
    {
        Print("[G] 🗑️ Usunięto ", totalRemoved, " poprzednich strzałek edytowanych pozycji");
    }
}

//+------------------------------------------------------------------+
//| Usuń wszystkie linie edytowanych pozycji (zachowana dla kompatybilności) |
//+------------------------------------------------------------------+
void ClearEditedPositionLines(long chartId)
{
    // Ta funkcja jest już nieaktualna - używamy ClearAllEditedPositionArrows()
    // Zachowana dla kompatybilności z istniejącym kodem
    
    int objectsTotal = ObjectsTotal(chartId);
    
    for(int i = objectsTotal - 1; i >= 0; i--)
    {
        string objectName = ObjectName(chartId, i);
        
        // Usuń obiekty zaczynające się od "EditedPosition_"
        if(StringFind(objectName, "EditedPosition_") == 0)
        {
            ObjectDelete(chartId, objectName);
            Print("[G] 🗑️ Usunięto linię: ", objectName);
        }
    }
}
