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

// Zmienne globalne dla systemu śledzenia pozycji
bool g_trackingActive = false;         // Czy śledzenie jest aktywne
datetime g_lastTrackingUpdate = 0;     // Ostatnia aktualizacja śledzenia
long g_currentTrackedTicket = 0;       // Aktualnie śledzone zlecenie
string g_trackingStatus = "";           // Status do wyświetlenia
int g_trackingCounter = 0;             // Licznik wykonanych sprawdzeń
const int MAX_TRACKING_CYCLES = 300;   // Maksymalna liczba cykli (5 minut)

// Zmienne globalne dla innych timerów
datetime g_lastPositionCheck = 0;      // Ostatnie sprawdzenie pozycji
datetime g_lastBreakCheck = 0;         // Ostatnie sprawdzenie przerw

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
    
    // Inicjalizacja zarządzania wolumenem - NOWY SYSTEM
    VolumeManager_Init();
    
    // Ustawienie timera
    int timerIntervalValue = Config_GetTimerInterval();
    EventSetTimer(timerIntervalValue);
    
    // Stwórz przycisk śledzenia pozycji
    CreateTrackingButton();
    
    Print("=== EA Nie_odjeb zainicjalizowany pomyślnie ===");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== Deinicjalizacja EA Nie_odjeb ===");
    
    // Wyłącz śledzenie pozycji
    if(g_trackingActive)
    {
        g_trackingActive = false;
        ClearAllEditedPositionArrows();
        ClearTrackingStatusFromAllCharts();
    }
    
    // Usuń przycisk śledzenia
    RemoveTrackingButton();
    
    EventKillTimer();
    DatabaseManager_Deinit();
    
    Print("EA Nie_odjeb zatrzymany. Powód: ", reason);
}

//+------------------------------------------------------------------+
//| Timer function - teraz z różnymi interwałami                     |
//+------------------------------------------------------------------+
void OnTimer()
{
    datetime currentTime = TimeCurrent();
    
    // NAJWYŻSZY PRIORYTET: Śledzenie edytowanej pozycji (co sekundę, jeśli aktywne)
    if(g_trackingActive)
    {
        ProcessPositionTracking();
    }
    
    // Sprawdzenie pozycji pod kątem maksymalnej straty (co 30 sekund)
    if(currentTime - g_lastPositionCheck >= 30)
    {
        Print("[TIMER-30s] 📊 Sprawdzenie pozycji pod kątem maksymalnej straty (", TimeToString(currentTime, TIME_SECONDS), ")");
        PositionManager_CheckAllPositionsForMaxLoss();
        g_lastPositionCheck = currentTime;
    }
    
    // Monitoring przerwy (co 30 sekund, działa tylko podczas przerwy)
    if(currentTime - g_lastBreakCheck >= 30)
    {
        Print("[TIMER-30s] ⏳ Monitoring przerwy i blokowanie trejdów (", TimeToString(currentTime, TIME_SECONDS), ")");
        BreakManager_MonitorAndBlockTrades();
        g_lastBreakCheck = currentTime;
        
        // NOWY: Regularnie czyść nieaktywne referencje volume manager
        VolumeManager_CleanupReferences();
    }
}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    switch(id)
    {
        case CHARTEVENT_OBJECT_CLICK:
        {
            if(sparam == "TrackingButton")
            {
                TogglePositionTracking();
                return;
            }
            break;
        }
        
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
                case 71:   // klawisz g - toggle śledzenia edytowanej pozycji (G jak goto)
                {
                    TogglePositionTracking();
                    break;
                }
                case 86:   // klawisz v - pokaż status referencji volume manager (V jak volume)
                {
                    Print("=== STATUS VOLUME MANAGER ===");
                    VolumeManager_PrintReferencesStatus();
                    VolumeManager_CleanupReferences();
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
            // NOWY SYSTEM: Reaguj tylko na zmiany SL, nie na wszystkie modyfikacje
            if(VolumeManager_IsStopLossModification(trans.order))
            {
                Print("[MAIN] 🔄 Wykryto modyfikację SL - wywołuję nowy system");
                VolumeManager_HandleStopLossChange(trans.order);
            }
            else
            {
                Print("[MAIN] ⚪ Modyfikacja zlecenia ", trans.order, " - nie dotyczy SL");
            }
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
            
            // DEBUG: Pokaż tylko jeśli śledzenie jest aktywne lub przy włączaniu
            if(g_trackingActive || ticket > 0)
            {
                Print("[G] 📆 Odczytano z bazy: ticket = ", ticket, " (string: '", ticket_str, "')");
            }
        }
        else
        {
            if(g_trackingActive)
                Print("[G] ⚠️ Nie można odczytać wartości ticket z bazy");
        }
    }
    else
    {
        if(g_trackingActive)
        {
            Print("[G] ⚠️ Brak danych komunikacji w bazie lub tabela nie istnieje");
            Print("[G] 📝 Upewnij się, że dziennik Python był uruchomiony (tworzy tabelę)");
        }
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
//| Nawiguj wykres do określonego czasu - POPRAWIONA WERSJA           |
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
    string symbol = ChartSymbol(chartId);
    ENUM_TIMEFRAMES period = (ENUM_TIMEFRAMES)ChartPeriod(chartId);
    
    Print("[G] 🔍 Nawigacja do czasu: ", TimeToString(targetTime));
    Print("[G] 📊 Symbol: ", symbol, ", Timeframe: ", EnumToString(period));
    
    // NOWA METODA: Użyj iBarShift do znalezienia dokładnego indeksu bara
    int targetBarIndex = iBarShift(symbol, period, targetTime, true);
    
    if(targetBarIndex < 0)
    {
        Print("[G] ❌ Nie można znaleźć bara dla czasu: ", TimeToString(targetTime));
        Print("[G] 💡 Możliwe przyczyny: czas sprzed dostępnej historii lub błędny symbol");
        return false;
    }
    
    Print("[G] 📐 Znaleziony bar na indeksie: ", targetBarIndex);
    
    // Sprawdź rzeczywisty czas znalezionego bara (dla weryfikacji)
    datetime foundBarTime = iTime(symbol, period, targetBarIndex);
    if(foundBarTime > 0)
    {
        Print("[G] 🕐 Rzeczywisty czas bara: ", TimeToString(foundBarTime));
        
        // Pokaż różnicę czasową jeśli istnieje
        int timeDiff = (int)(targetTime - foundBarTime);
        if(timeDiff != 0)
        {
            Print("[G] ⏰ Różnica czasowa: ", timeDiff, " sekund (normalne dla timeframe > M1)");
        }
    }
    
    // Wyłącz autoscroll przed nawigacją (ważne!)
    bool autoScrollWasOn = (bool)ChartGetInteger(chartId, CHART_AUTOSCROLL);
    if(autoScrollWasOn)
    {
        ChartSetInteger(chartId, CHART_AUTOSCROLL, false);
        Print("[G] 🔧 Wyłączono autoscroll");
    }
    
    // GŁÓWNA NAWIGACJA: Przesuń wykres do znalezionego bara
    // Używamy CHART_END z ujemnym przesunięciem (najbardziej niezawodne)
    bool success = ChartNavigate(chartId, CHART_END, -targetBarIndex); // dodalem 5 barow by strzalka nie byla rysowana na samym boku wykresu
    
    if(success)
    {
        Print("[G] ✅ Wykres przesunięty do bara ", targetBarIndex, " (metoda CHART_END)");
        
        // Sprawdź rezultat nawigacji
        int newFirstVisibleBar = (int)ChartGetInteger(chartId, CHART_FIRST_VISIBLE_BAR);
        Print("[G] 📍 Pierwszy widoczny bar po nawigacji: ", newFirstVisibleBar);
        
        // Opcjonalnie: przywróć autoscroll jeśli był włączony
        if(autoScrollWasOn)
        {
            // Czekaj chwilę przed przywróceniem autoscroll
            Sleep(100);
            ChartSetInteger(chartId, CHART_AUTOSCROLL, true);
            Print("[G] 🔧 Przywrócono autoscroll");
        }
        
        return true;
    }
    
    // METODA ZAPASOWA 1: Spróbuj z CHART_BEGIN
    Print("[G] 🔄 Metoda CHART_END nie zadziałała, próbuję CHART_BEGIN...");
    
    // Oblicz pozycję od początku historii
    int totalBars = iBars(symbol, period);
    if(totalBars > 0)
    {
        int barsFromBegin = totalBars - targetBarIndex - 1 ; // +5 barów marginesu
        success = ChartNavigate(chartId, CHART_BEGIN, barsFromBegin);
        
        if(success)
        {
            Print("[G] ✅ Wykres przesunięty (metoda CHART_BEGIN), bars from begin: ", barsFromBegin);
            
            if(autoScrollWasOn)
            {
                Sleep(100);
                ChartSetInteger(chartId, CHART_AUTOSCROLL, true);
            }
            
            return true;
        }
    }
    
    // METODA ZAPASOWA 2: Spróbuj z CHART_CURRENT_POS
    Print("[G] 🔄 Próbuję CHART_CURRENT_POS...");
    
    int currentFirstBar = (int)ChartGetInteger(chartId, CHART_FIRST_VISIBLE_BAR);
    int shiftFromCurrent = currentFirstBar - targetBarIndex;
    
    success = ChartNavigate(chartId, CHART_CURRENT_POS, shiftFromCurrent);
    
    if(success)
    {
        Print("[G] ✅ Wykres przesunięty (metoda CHART_CURRENT_POS), shift: ", shiftFromCurrent);
        
        if(autoScrollWasOn)
        {
            Sleep(100);
            ChartSetInteger(chartId, CHART_AUTOSCROLL, true);
        }
        
        return true;
    }
    
    // Wszystkie metody zawiodły
    Print("[G] ❌ Nie udało się przesunąć wykresu żadną metodą");
    Print("[G] 🔧 Błąd ChartNavigate: ", GetLastError());
    Print("[G] 💡 Spróbuj ręcznie przejść do czasu: ", TimeToString(targetTime));
    Print("[G] 📝 Bar do znalezienia: indeks ", targetBarIndex, " (licząc od końca)");
    
    // Przywróć autoscroll jeśli był włączony
    if(autoScrollWasOn)
    {
        ChartSetInteger(chartId, CHART_AUTOSCROLL, true);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Dodaj strzałkę w zależności od typu pozycji                      |
//+------------------------------------------------------------------+
void AddVerticalLineAtTime(long chartId, datetime openTime, long ticket)
{
    // NIE usuwamy strzałek tutaj - robi to już system śledzenia
    
    string arrowName = "EditedPosition_" + IntegerToString(ticket);
    
    // Pobierz dane pozycji do określenia typu
    bool isBuyPosition = false;
    bool positionFound = false;
    
    // Sprawdź czy to otwarta pozycja
    if(PositionSelectByTicket(ticket))
    {
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        isBuyPosition = (type == POSITION_TYPE_BUY);
        positionFound = true;
    }
    else if(HistorySelectByPosition(ticket))
    {
        // Pozycja zamknięta - sprawdź historię
        int dealsTotal = HistoryDealsTotal();
        for(int i = 0; i < dealsTotal; i++)
        {
            ulong deal_ticket = HistoryDealGetTicket(i);
            if(deal_ticket > 0)
            {
                long dealEntry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                if(dealEntry == DEAL_ENTRY_IN)
                {
                    ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
                    isBuyPosition = (deal_type == DEAL_TYPE_BUY);
                    positionFound = true;
                    break;
                }
            }
        }
    }
    
    if(!positionFound)
    {
        Print("[G] ⚠️ Nie udało się określić typu pozycji dla ticket ", ticket);
        return;
    }
    
    // Pobierz zakres cen na wykresie
    double chartHigh = ChartGetDouble(chartId, CHART_PRICE_MAX);
    double chartLow = ChartGetDouble(chartId, CHART_PRICE_MIN);
    
    // Pobierz cenę świeczki w czasie otwarcia pozycji
    string symbol = ChartSymbol(chartId);
    ENUM_TIMEFRAMES period = (ENUM_TIMEFRAMES)ChartPeriod(chartId);
    
    // Znajdź świeczkę najbliższą czasowi otwarcia
    int candleIndex = iBarShift(symbol, period, openTime, true);
    double candleHigh = iHigh(symbol, period, candleIndex);
    double candleLow = iLow(symbol, period, candleIndex);
    
    // Ustaw pozycję i typ strzałki w zależności od typu pozycji
    double arrowPrice;
    ENUM_OBJECT arrowType;
    string positionTypeText;
    
    if(isBuyPosition)
    {
        // BUY: Strzałka do góry, pod świeczką
        arrowType = OBJ_ARROW_UP;
        double margin = (chartHigh - chartLow) * 0.02; // 2% marginesu
        arrowPrice = candleLow - margin;
        positionTypeText = "BUY";
    }
    else
    {
        // SELL: Strzałka w dół, nad świeczką
        arrowType = OBJ_ARROW_DOWN;
        double margin = (chartHigh - chartLow) * 0.02; // 2% marginesu
        arrowPrice = candleHigh + margin;
        positionTypeText = "SELL";
    }
    
    // Stwórz strzałkę
    if(ObjectCreate(chartId, arrowName, arrowType, 0, openTime, arrowPrice))
    {
        // Ustaw właściwości strzałki
        ObjectSetInteger(chartId, arrowName, OBJPROP_COLOR, clrBlack);  // Różowy kolor
        ObjectSetInteger(chartId, arrowName, OBJPROP_WIDTH, 3);           // Większa grubość
        ObjectSetInteger(chartId, arrowName, OBJPROP_BACK, false);        // Na pierwszym planie
        
        // Dodaj opis
        string description = StringFormat("%s %d", positionTypeText, ticket);
        ObjectSetString(chartId, arrowName, OBJPROP_TEXT, description);
        
        Print("[G] ", (isBuyPosition ? "⬆️" : "⬇️"), " Dodano strzałkę ", positionTypeText, " dla pozycji ", ticket);
        
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
//| Toggle (włącz/wyłącz) śledzenie pozycji                          |
//+------------------------------------------------------------------+
void TogglePositionTracking()
{
    if(g_trackingActive)
    {
        // Wyłącz śledzenie
        g_trackingActive = false;
        g_currentTrackedTicket = 0;
        g_trackingStatus = "";
        g_trackingCounter = 0; // Resetuj licznik
        
        // Usuń wszystkie strzałki śledzenia
        ClearAllEditedPositionArrows();
        
        // Usuń status z wykresów
        ClearTrackingStatusFromAllCharts();
        
        // Zaktualizuj przycisk na czerwony
        UpdateTrackingButton();
        
        Print("[G] ❌ Śledzenie pozycji WYŁĄCZONE");
    }
    else
    {
        // Włącz śledzenie
        g_trackingActive = true;
        g_lastTrackingUpdate = 0; // Wymusz natychmiastową aktualizację
        g_currentTrackedTicket = 0; // Resetuj ticket żeby wymusić pełną aktualizację
        g_trackingCounter = 0; // Resetuj licznik
        
        // Zaktualizuj przycisk na zielony
        UpdateTrackingButton();
        
        Print("[G] ✅ Śledzenie pozycji WŁĄCZONE - maks. ", MAX_TRACKING_CYCLES, " cykli (5 minut)");
        
        // NATYCHMIASTOWA PEŁNA AKTUALIZACJA
        long currentTicket = ReadCurrentEditTicketFromDatabase();
        
        if(currentTicket > 0)
        {
            Print("[G] 🔄 Rozpoczynam śledzenie pozycji: ", currentTicket);
            g_currentTrackedTicket = currentTicket;
            
            // Pokaż pozycję natychmiast
            ShowEditedPositionOnChart();
            
            // Ustaw status
            g_trackingStatus = StringFormat("Śledzenie aktywne | Pozycja: %d | Cykl: %d/%d | %s", 
                                           currentTicket, g_trackingCounter, MAX_TRACKING_CYCLES, TimeToString(TimeCurrent(), TIME_SECONDS));
            UpdateTrackingStatusOnAllCharts();
        }
        else
        {
            Print("[G] ⚠️ Brak pozycji do śledzenia w bazie danych");
            g_trackingStatus = StringFormat("Brak edytowanej pozycji | Cykl: %d/%d", g_trackingCounter, MAX_TRACKING_CYCLES);
            UpdateTrackingStatusOnAllCharts();
        }
        
        // Zaktualizuj czas ostatniej aktualizacji
        g_lastTrackingUpdate = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Przetwarzaj śledzenie pozycji (wywoływane co sekundę)              |
//+------------------------------------------------------------------+
void ProcessPositionTracking()
{
    datetime currentTime = TimeCurrent();
    
    // Sprawdź czy minęła JEDNA SEKUNDA od ostatniej aktualizacji (nie minuta!)
    if(currentTime - g_lastTrackingUpdate < 1)
    {
        return; // Za szybko, poczekaj
    }
    
    g_lastTrackingUpdate = currentTime;
    g_trackingCounter++; // Zwiększ licznik
    
    // Sprawdź limit cykli (300 = 5 minut)
    if(g_trackingCounter >= MAX_TRACKING_CYCLES)
    {
        Print("[G] ⏰ Osiągnięto limit 300 cykli (5 minut) - automatyczne wyłączenie");
        g_trackingActive = false;
        g_trackingCounter = 0;
        ClearAllEditedPositionArrows();
        ClearTrackingStatusFromAllCharts();
        UpdateTrackingButton(); // Zaktualizuj przycisk na czerwony
        return;
    }
    
    // DEBUG: Pokaż że funkcja działa (co 10 sekund)
    if(g_trackingCounter % 10 == 1)
    {
        Print("[G] 🔄 Śledzenie działa... (cykl #", g_trackingCounter, "/", MAX_TRACKING_CYCLES, ")");
    }
    
    // Odczytaj aktualny ticket z bazy
    long currentTicket = ReadCurrentEditTicketFromDatabase();
    
    if(currentTicket <= 0)
    {
        // Brak edytowanej pozycji
        if(g_currentTrackedTicket != 0)
        {
            // Poprzednio była pozycja, teraz jej nie ma
            ClearAllEditedPositionArrows();
            g_currentTrackedTicket = 0;
            g_trackingStatus = "Brak edytowanej pozycji";
            UpdateTrackingStatusOnAllCharts();
            Print("[G] 📍 Śledzenie: Brak edytowanej pozycji");
        }
        else
        {
            // Aktualizuj status z czasem i licznikiem
            g_trackingStatus = StringFormat("Brak edytowanej pozycji | Cykl: %d/%d | %s", 
                                           g_trackingCounter, MAX_TRACKING_CYCLES, TimeToString(currentTime, TIME_SECONDS));
            UpdateTrackingStatusOnAllCharts();
        }
        return;
    }
    
    // Sprawdź czy pozycja się zmieniła
    if(currentTicket != g_currentTrackedTicket)
    {
        g_currentTrackedTicket = currentTicket;
        Print("[G] 🔄 Śledzenie: Nowa pozycja ", currentTicket);
        
        // Usuń stare strzałki
        ClearAllEditedPositionArrows();
        
        // Pokaż nową pozycję
        ShowEditedPositionOnChart();
    }
    
    // Zawsze aktualizuj status na wykresach (z aktualnym czasem i licznikiem)
    g_trackingStatus = StringFormat("Śledzenie aktywne | Pozycja: %d | Cykl: %d/%d | %s", 
                                   currentTicket, g_trackingCounter, MAX_TRACKING_CYCLES, TimeToString(currentTime, TIME_SECONDS));
    UpdateTrackingStatusOnAllCharts();
}

//+------------------------------------------------------------------+
//| Aktualizuj status śledzenia na wszystkich wykresach               |
//+------------------------------------------------------------------+
void UpdateTrackingStatusOnAllCharts()
{
    long chartId = ChartFirst();
    
    while(chartId >= 0)
    {
        // Dodaj/aktualizuj status w lewym górnym rogu
        string statusName = "TrackingStatus";
        
        // Usuń stary status
        ObjectDelete(chartId, statusName);
        
        if(g_trackingStatus != "")
        {
            // Dodaj nowy status
            if(ObjectCreate(chartId, statusName, OBJ_LABEL, 0, 0, 0))
            {
                ObjectSetInteger(chartId, statusName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
                ObjectSetInteger(chartId, statusName, OBJPROP_XDISTANCE, 10);
                ObjectSetInteger(chartId, statusName, OBJPROP_YDISTANCE, 30);
                ObjectSetInteger(chartId, statusName, OBJPROP_COLOR, clrLimeGreen);
                ObjectSetInteger(chartId, statusName, OBJPROP_FONTSIZE, 9);
                ObjectSetString(chartId, statusName, OBJPROP_TEXT, g_trackingStatus);
                ObjectSetString(chartId, statusName, OBJPROP_FONT, "Arial");
            }
        }
        
        chartId = ChartNext(chartId);
    }
}

//+------------------------------------------------------------------+
//| Usuń status śledzenia ze wszystkich wykresów                     |
//+------------------------------------------------------------------+
void ClearTrackingStatusFromAllCharts()
{
    long chartId = ChartFirst();
    
    while(chartId >= 0)
    {
        ObjectDelete(chartId, "TrackingStatus");
        ChartRedraw(chartId);
        chartId = ChartNext(chartId);
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

//+------------------------------------------------------------------+
//| Stwórz przycisk śledzenia pozycji                                 |
//+------------------------------------------------------------------+
void CreateTrackingButton()
{
    long chartId = ChartID();
    string buttonName = "TrackingButton";
    
    // Usuń istniejący przycisk jeśli jest
    ObjectDelete(chartId, buttonName);
    
    // Stwórz przycisk
    if(ObjectCreate(chartId, buttonName, OBJ_BUTTON, 0, 0, 0))
    {
        // Właściwości przycisku
        ObjectSetInteger(chartId, buttonName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(chartId, buttonName, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(chartId, buttonName, OBJPROP_YDISTANCE, 60);
        ObjectSetInteger(chartId, buttonName, OBJPROP_XSIZE, 120);
        ObjectSetInteger(chartId, buttonName, OBJPROP_YSIZE, 25);
        ObjectSetString(chartId, buttonName, OBJPROP_TEXT, "TRACK: OFF");
        ObjectSetString(chartId, buttonName, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(chartId, buttonName, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(chartId, buttonName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(chartId, buttonName, OBJPROP_BGCOLOR, clrCrimson); // Czerwony gdy wyłączony
        ObjectSetInteger(chartId, buttonName, OBJPROP_BORDER_COLOR, clrBlack);
        ObjectSetInteger(chartId, buttonName, OBJPROP_BACK, false);
        ObjectSetInteger(chartId, buttonName, OBJPROP_STATE, false);
        ObjectSetInteger(chartId, buttonName, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(chartId, buttonName, OBJPROP_SELECTED, false);
        
        Print("[INIT] ⚙️ Przycisk śledzenia pozycji utworzony");
    }
    else
    {
        Print("[ERROR] Nie udało się utworzyć przycisku: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Zaktualizuj wygląd przycisku                                     |
//+------------------------------------------------------------------+
void UpdateTrackingButton()
{
    long chartId = ChartID();
    string buttonName = "TrackingButton";
    
    if(ObjectFind(chartId, buttonName) >= 0)
    {
        if(g_trackingActive)
        {
            // Włączony - zielony przycisk
            ObjectSetString(chartId, buttonName, OBJPROP_TEXT, "TRACK: ON");
            ObjectSetInteger(chartId, buttonName, OBJPROP_BGCOLOR, clrForestGreen);
            ObjectSetInteger(chartId, buttonName, OBJPROP_COLOR, clrWhite);
        }
        else
        {
            // Wyłączony - czerwony przycisk
            ObjectSetString(chartId, buttonName, OBJPROP_TEXT, "TRACK: OFF");
            ObjectSetInteger(chartId, buttonName, OBJPROP_BGCOLOR, clrCrimson);
            ObjectSetInteger(chartId, buttonName, OBJPROP_COLOR, clrWhite);
        }
        
        ChartRedraw(chartId);
    }
}

//+------------------------------------------------------------------+
//| Usuń przycisk śledzenia pozycji                                  |
//+------------------------------------------------------------------+
void RemoveTrackingButton()
{
    long chartId = ChartID();
    string buttonName = "TrackingButton";
    
    if(ObjectFind(chartId, buttonName) >= 0)
    {
        ObjectDelete(chartId, buttonName);
        ChartRedraw(chartId);
        Print("[DEINIT] 🗑️ Przycisk śledzenia pozycji usunięty");
    }
}
