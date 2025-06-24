//+------------------------------------------------------------------+
//|                                              BreakManager.mqh |
//|                    Zarządzanie przerwami dla EA Nie_odjeb        |
//+------------------------------------------------------------------+

#ifndef BREAKMANAGER_MQH
#define BREAKMANAGER_MQH

#include <Trade\Trade.mqh>
#include "Config.mqh"
#include "DataStructures.mqh"

// Zmienne globalne dla zarządzania przerwami
ClosedPosition g_lastPositions[3];
datetime g_przerwa_do = 0;
bool g_mozna_wykonac_trade = true;
string g_break_reason = ""; // Powód przerwy
bool g_break_alert_shown = false; // Czy alert jest już wyświetlony

//+------------------------------------------------------------------+
//| Inicjalizacja zarządzania przerwami                              |
//+------------------------------------------------------------------+
void BreakManager_Init()
{
    // Inicjalizacja pozycji
    for(int i = 0; i < 3; i++)
    {
        g_lastPositions[i].symbol = "";
        g_lastPositions[i].profit = 0.0;
        g_lastPositions[i].volume = 0.0;
        g_lastPositions[i].closeTime = 0;
        g_lastPositions[i].ProfitPerUnit = 0.0;
    }
    
    Print("Zarządzanie przerwami zainicjalizowane");
}

//+------------------------------------------------------------------+
//| Sprawdzenie dziennych limitów strat                              |
//+------------------------------------------------------------------+
void BreakManager_CheckDailyLimits()
{
    datetime now = TimeCurrent();
    MqlDateTime today;
    TimeToStruct(now, today);
    
    today.hour = 0;
    today.min = 0;
    today.sec = 0;
    
    datetime startOfDay = StructToTime(today);
    
    today.hour = 23;
    today.min = 50;
    today.sec = 0;
    
    datetime endOfDay = StructToTime(today);
    
    HistorySelect(startOfDay, now);
    
    double totalDailyProfit = 0.0;
    
    int totalDeals = HistoryDealsTotal();
    for(int i = 0; i < totalDeals; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket <= 0) continue;
        
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
        {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            totalDailyProfit += profit;
        }
    }
    
    if(totalDailyProfit < -Config_GetMaxDailyLoss())
    {
        g_przerwa_do = endOfDay;
        g_mozna_wykonac_trade = false;
        g_break_reason = "dzienny limit strat";
        g_break_alert_shown = false;
        
        // Dźwięk ostrzegawczy
        PlaySound("stops.wav");
        
        // Wyświetlenie na wykresie (nieblokujące)
        string alertText = "\n\n=== DZIENNY LIMIT STRAT ===\n";
        alertText += "Całkowity profit: " + DoubleToString(totalDailyProfit, 2) + "\n";
        alertText += "Trading zablokowany do: " + TimeToString(g_przerwa_do) + "\n";
        alertText += "===========================";
        Comment(alertText);
        
        Print("UWAGA: Osiągnięto dzienny limit strat!");
        Print("Całkowity profit: ", DoubleToString(totalDailyProfit, 2));
        Print("Trading zablokowany do: ", TimeToString(g_przerwa_do));
    }
    else 
    {
        Print(" ### aktualny Profit: ", totalDailyProfit);
    }
}

//+------------------------------------------------------------------+
//| Pobierz ostatnie zamknięte pozycje                               |
//+------------------------------------------------------------------+
void BreakManager_GetLastClosedPositions()
{
    // Inicjalizacja pozycji
    for(int i = 0; i < 3; i++)
    {
        g_lastPositions[i].symbol = "";
        g_lastPositions[i].profit = 0.0;
        g_lastPositions[i].volume = 0.0;
        g_lastPositions[i].closeTime = 0;
        g_lastPositions[i].ProfitPerUnit = 0.0;
    }
    
    datetime now = TimeCurrent();
    MqlDateTime today;
    TimeToStruct(now, today);
    
    today.hour = 0;
    today.min = 0;
    today.sec = 0;
    
    datetime startOfDay = StructToTime(today);
    
    HistorySelect(startOfDay, now);
    int totalDeals = HistoryDealsTotal();
    
    int positionCount = 0;
    
    for(int i = totalDeals - 1; i >= 0 && positionCount < 3; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket <= 0) continue;
        
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
        {
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            double default_SL = Config_GetDefaultSLForSymbol(symbol);
            
            double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double profitPerUnit = (volume > 0) ? profit / volume : 0;
            
            if(profitPerUnit < (-0.5 * default_SL) || profitPerUnit > 0.6 * default_SL)
            {
                g_lastPositions[positionCount].symbol = symbol;
                g_lastPositions[positionCount].profit = profit;
                g_lastPositions[positionCount].volume = volume;
                g_lastPositions[positionCount].closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
                g_lastPositions[positionCount].ProfitPerUnit = profitPerUnit;
                
                positionCount++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Sprawdzenie serii strat                                          |
//+------------------------------------------------------------------+
bool BreakManager_CheckLossStreak()
{
    int liczbaStratnych = 0;
    Print("last positions:------------------ ");
    
    // Sprawdzamy od końca tablicy
    for(int i = 0; i <= 2; i++)
    {
        Print("last xxxxxxxxxxxxxxxxxxxxxxxxxx: ");
        
        if(g_lastPositions[i].ProfitPerUnit < 0 && g_lastPositions[i].closeTime > 0)
        {
            liczbaStratnych++;
        }
        else
        {
            break;  // Przerywamy liczenie przy pierwszej dodatniej lub pustej pozycji
        }
    }
    
    // Ustawiamy przerwę w zależności od liczby stratnych pozycji
    if(liczbaStratnych == 2)
    {
        if(!(g_lastPositions[0].closeTime-g_lastPositions[1].closeTime>1800))
        {
            g_przerwa_do = g_lastPositions[0].closeTime + Config_GetBreak2Losses() * 60;
            g_mozna_wykonac_trade = false;
            g_break_reason = "2 kolejne straty";
            g_break_alert_shown = false;
            Print("UWAGA: Przerwa w tradingu na ", Config_GetBreak2Losses(), " minut z powodu 2 kolejnych strat!");
            return true;
        }
        else 
        {
            Print("są 2 stratne, ale przerwa między ostatnimi trejdami była więcej niż 30 minut");
        }
    }
    else if(liczbaStratnych == 3)
    {
        if(!(g_lastPositions[0].closeTime-g_lastPositions[1].closeTime>1800))
        {
            g_przerwa_do = g_lastPositions[0].closeTime + Config_GetBreak3Losses() * 60;
            g_mozna_wykonac_trade = false;
            g_break_reason = "3 kolejne straty";
            g_break_alert_shown = false;
            Print("UWAGA: Przerwa w tradingu na ", Config_GetBreak3Losses(), " minut z powodu 3 kolejnych strat!");
            return true;
        }
        else 
        {
            Print("są 3 stratne, ale przerwa między ostatnimi trejdami była więcej niż 30 minut");
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Sprawdzenie czy można wykonać trade                              |
//+------------------------------------------------------------------+
bool BreakManager_CanTrade()
{
    datetime teraz = TimeCurrent();
    return g_mozna_wykonac_trade && teraz >= g_przerwa_do;
}

//+------------------------------------------------------------------+
//| Zapis daty przerwy do pliku CSV                                  |
//+------------------------------------------------------------------+
void BreakManager_SaveDateToCSV(datetime valueToSave)
{
    string fileName = "przerwa_do.csv";
    int fileHandle = FileOpen(fileName, FILE_WRITE | FILE_CSV);
    
    if(fileHandle != INVALID_HANDLE)
    {
        FileWrite(fileHandle, valueToSave);
        FileClose(fileHandle);
        Print("Zapisano wartość: ", valueToSave);
    }
    else
    {
        Print("Błąd zapisu pliku CSV: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Obsługa zamkniętej pozycji                                       |
//+------------------------------------------------------------------+
void BreakManager_HandleClosedPosition()
{
    datetime teraz = TimeCurrent();
    
    // Jeśli jesteśmy w przerwie, sprawdzamy czy już minęła
    if(!g_mozna_wykonac_trade && teraz >= g_przerwa_do)
    {
        g_mozna_wykonac_trade = true;
        Print("Przerwa w tradingu zakończona. Można wznawiać transakcje.");
    }
    
    // Pobieranie pozycji
    BreakManager_GetLastClosedPositions();
    
    // Sprawdzamy serię strat
    BreakManager_CheckLossStreak();
    
    // Wyświetlenie informacji o pozycjach
    for(int i = 0; i < 3; i++)
    {
        if(g_lastPositions[i].closeTime > 0)
        {
            Print("Pozycja ", i+1, ":");
            Print("  Skorygowany profit: ", DoubleToString(g_lastPositions[i].ProfitPerUnit, 2));
            Print("  Czas zamknięcia: ", TimeToString(g_lastPositions[i].closeTime));
        }
    }
    
    BreakManager_CheckDailyLimits();
    
    // Dodatkowe informacje o możliwości wykonania trade
    if(teraz < g_przerwa_do)
    {
        // Dźwięk ostrzegawczy
        PlaySound("stops.wav");
        
        // Wyświetlenie na wykresie (nieblokujące)
        string alertText = "\n\n=== HANDEL ZABLOKOWANY ===\n";
        alertText += "Handel zablokowany do: " + TimeToString(g_przerwa_do) + "\n";
        alertText += "Powód: " + g_break_reason + "\n";
        
        datetime pozostalo = g_przerwa_do - teraz;
        int minut = (int)(pozostalo / 60);
        alertText += "Pozostało: " + IntegerToString(minut) + " minut\n";
        alertText += "=========================";
        Comment(alertText);
        
        Print("UWAGA: Handel zablokowany do: " + TimeToString(g_przerwa_do));
    }
    else 
    {
        if(!g_mozna_wykonac_trade)
        {
            Print("Przerwa z powodu kolejnych strat była do: " + TimeToString(g_przerwa_do-3600));
        }
    }
    
    // Zapisanie do której mamy przerwę do pliku csv
    BreakManager_SaveDateToCSV(g_przerwa_do);
}

//+------------------------------------------------------------------+
//| Wyświetlenie alertu o przerwie                                  |
//+------------------------------------------------------------------+
void BreakManager_ShowBreakAlert(string action)
{
    if(!g_break_alert_shown)
    {
        // Dźwięk ostrzegawczy
        PlaySound("alert.wav");
        
        // Aktualizacja flagi
        g_break_alert_shown = true;
    }
    
    // Przygotowanie tekstu alertu
    string alertText = "\n\n\n=== TRADING ZABLOKOWANY ===\n";
    alertText += action + "\n";
    alertText += "Powód: " + g_break_reason + "\n";
    alertText += "Koniec przerwy: " + TimeToString(g_przerwa_do, TIME_DATE|TIME_MINUTES) + "\n";
    
    datetime teraz = TimeCurrent();
    int pozostalo_minut = (int)((g_przerwa_do - teraz) / 60);
    if(pozostalo_minut > 0)
    {
        alertText += "Pozostało: " + IntegerToString(pozostalo_minut) + " minut\n";
    }
    alertText += "==========================";
    
    // Wyświetlenie na wykresie (nieblokujące)
    Comment(alertText);
    
    // Log w dzienniku
    Print("*** TRADING ZABLOKOWANY *** ", action, " - ", g_break_reason, " do ", TimeToString(g_przerwa_do));
}

//+------------------------------------------------------------------+
//| Monitoring i usuwanie pozycji/zleceń podczas przerwy            |
//+------------------------------------------------------------------+
void BreakManager_MonitorAndBlockTrades()
{
    // Monitoring działa tylko podczas przerwy
    if(g_mozna_wykonac_trade) 
    {
        // Jeśli przerwa się zakończyła, czyścimy alert
        if(g_break_alert_shown)
        {
            Comment(""); // Usunięcie tekstu z wykresu
            g_break_alert_shown = false;
            g_break_reason = "";
            Print("Przerwa zakończona - trading odblokowany");
        }
        return;
    }
    
    datetime teraz = TimeCurrent();
    
    // Sprawdzenie czy przerwa już minęła
    if(teraz >= g_przerwa_do)
    {
        g_mozna_wykonac_trade = true;
        Comment(""); // Usunięcie tekstu z wykresu
        g_break_alert_shown = false;
        g_break_reason = "";
        Print("Przerwa automatycznie zakończona - trading odblokowany");
        return;
    }
    
    // Jeśteesmy w przerwie - sprawdzamy pozycje i zlecenia
    CTrade trade;
    bool foundViolation = false;
    
    // 1. Sprawdzenie otwartych pozycji
    int totalPositions = PositionsTotal();
    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong positionTicket = PositionGetTicket(i);
        if(positionTicket > 0)
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            
            // Jeśli pozycja została otwarta podczas przerwy
            if(openTime >= (g_przerwa_do - Config_GetBreak2Losses() * 60))
            {
                if(trade.PositionClose(positionTicket))
                {
                    BreakManager_ShowBreakAlert("Usunięto pozycję: " + symbol);
                    foundViolation = true;
                }
            }
        }
    }
    
    // 2. Sprawdzenie oczekujących zleceń
    int totalOrders = OrdersTotal();
    for(int i = totalOrders - 1; i >= 0; i--)
    {
        ulong orderTicket = OrderGetTicket(i);
        if(orderTicket > 0)
        {
            string symbol = OrderGetString(ORDER_SYMBOL);
            datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
            
            // Jeśli zlecenie zostało złożone podczas przerwy
            if(setupTime >= (g_przerwa_do - Config_GetBreak2Losses() * 60))
            {
                if(trade.OrderDelete(orderTicket))
                {
                    BreakManager_ShowBreakAlert("Usunięto zlecenie: " + symbol);
                    foundViolation = true;
                }
            }
        }
    }
    
    // 3. Wyświetlenie ciągłego alertu o przerwie (co 30 sekund)
    static datetime lastAlertTime = 0;
    if(teraz - lastAlertTime >= 30)
    {
        BreakManager_ShowBreakAlert("PRZERWA W TRADINGU");
        lastAlertTime = teraz;
    }
}

//+------------------------------------------------------------------+
//| Sprawdzenie czy nowa transakcja narusza przerwę                  |
//+------------------------------------------------------------------+
void BreakManager_CheckNewTransaction(const MqlTradeTransaction& trans)
{
    // Jeśli nie ma przerwy, nic nie robimy
    if(g_mozna_wykonac_trade) return;
    
    datetime teraz = TimeCurrent();
    
    // Sprawdzenie czy przerwa już minęła
    if(teraz >= g_przerwa_do)
    {
        g_mozna_wykonac_trade = true;
        Comment("");
        g_break_alert_shown = false;
        g_break_reason = "";
        return;
    }
    
    // Reagujemy na nowe pozycje i zlecenia
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
        {
            // Uruchomienie pełnego monitoringu (sprawdzi i usunie jeśli trzeba)
            BreakManager_MonitorAndBlockTrades();
        }
    }
    else if(trans.type == TRADE_TRANSACTION_ORDER_ADD)
    {
        // Uruchomienie pełnego monitoringu (sprawdzi i usunie jeśli trzeba)
        BreakManager_MonitorAndBlockTrades();
    }
}

#endif // BREAKMANAGER_MQH
