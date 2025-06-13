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
    PositionManager_CheckAllPositionsForMaxLoss();
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
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
    // Obsługa zamknięcia pozycji - zarządzanie przerwami
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        ulong dealTicket = trans.deal;
        if(dealTicket > 0 && HistoryDealSelect(dealTicket))
        {
            if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
                Print("OnTradeTransaction: Wykryto zamkniętą transakcję");
                BreakManager_HandleClosedPosition();
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
