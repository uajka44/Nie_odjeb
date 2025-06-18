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
