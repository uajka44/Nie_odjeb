//+------------------------------------------------------------------+
//|                                            PositionManager.mqh |
//|                  Zarządzanie pozycjami dla EA Nie_odjeb          |
//+------------------------------------------------------------------+

#ifndef POSITIONMANAGER_MQH
#define POSITIONMANAGER_MQH

#include "Config.mqh"
#include <Trade\Trade.mqh>

// Używamy globalnej instancji CTrade z VolumeManager
extern CTrade g_Trade;

//+------------------------------------------------------------------+
//| Inicjalizacja zarządzania pozycjami                              |
//+------------------------------------------------------------------+
void PositionManager_Init()
{
    Print("Zarządzanie pozycjami zainicjalizowane");
}

//+------------------------------------------------------------------+
//| Sprawdzenie i modyfikacja stop loss dla pozycji                  |
//+------------------------------------------------------------------+
void PositionManager_CheckPositionStopLoss(ulong ticket)
{
    if(PositionSelectByTicket(ticket))
    {   
        string position_symbol = PositionGetString(POSITION_SYMBOL);
        double current_market_price_ask = NormalizeDouble(SymbolInfoDouble(position_symbol, SYMBOL_ASK), _Digits);
        double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
        double stop_loss_price = PositionGetDouble(POSITION_SL);
        double stop_loss_distance = 0;
        
        // Pobierz maksymalny stop loss dla danego symbolu
        double max_sl_points = Config_GetMaxSLForSymbol(position_symbol);
        double max_sl_price = 0;
              
        Print("Symbol: " + position_symbol + ", max SL: " + DoubleToString(max_sl_points, 5));
                    
        // Sprawdzenie typu pozycji (BUY lub SELL) i obliczenie odległości SL
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            stop_loss_distance = (price_open - stop_loss_price); 
            max_sl_price = price_open - max_sl_points;
        }
        else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            stop_loss_distance = (stop_loss_price - price_open);
            max_sl_price = price_open + max_sl_points;                      
        }
               
        Print("sl pozycji nr ", ticket, " = ", stop_loss_price);
        
        if(stop_loss_price == 0)
        {
            Print("Brak stop loss dla pozycji " + IntegerToString(ticket) + ", symbol: " + position_symbol);
            if(g_Trade.PositionModify(ticket, max_sl_price, PositionGetDouble(POSITION_TP)))                   
                Print("zmiana stop loss, jako że go nie było, dla ticket ", ticket);                
        }
               
        if(stop_loss_distance > max_sl_points)
        { 
            if(g_Trade.PositionModify(ticket, max_sl_price, PositionGetDouble(POSITION_TP)))     
                Print("zmiana stop loss: " + DoubleToString(max_sl_price, 5) + ", symbol: " + position_symbol + ", max SL: " + DoubleToString(max_sl_points, 5));         
        }
    }
}

//+------------------------------------------------------------------+
//| Sprawdzenie wszystkich pozycji                                   |
//+------------------------------------------------------------------+
void PositionManager_CheckAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        PositionManager_CheckPositionStopLoss(ticket);
    }
}

//+------------------------------------------------------------------+
//| Sprawdzanie pozycji pod kątem maksymalnej straty                 |
//+------------------------------------------------------------------+
void PositionManager_CheckAllPositionsForMaxLoss()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        double max_sl_price = 0;
        
        if(PositionSelectByTicket(ticket))
        {   
            string position_symbol = PositionGetString(POSITION_SYMBOL);
            double current_market_price_ask = NormalizeDouble(SymbolInfoDouble(position_symbol, SYMBOL_ASK), _Digits);
            Print("Profit: " + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2));

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) // buy
            {
                max_sl_price = PositionGetDouble(POSITION_PRICE_OPEN) - Config_GetMaxSLForSymbol(position_symbol);
                if (current_market_price_ask < max_sl_price)
                {
                    Print("spełniony warunek, przekroczyliśmy stratę z buy'a, powinno zamknąć"); 
                    if(g_Trade.PositionClose(ticket))                             
                        Print("Pozycja " + IntegerToString(ticket) + " zamknięta gdyż na pozycji jest za duża strata");     
                    else
                        Print("Błąd zamykania pozycji: ", GetLastError()); 
                }                                      
            }              
            
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)   // sell
            {
                max_sl_price = PositionGetDouble(POSITION_PRICE_OPEN) + Config_GetMaxSLForSymbol(position_symbol);
                if (current_market_price_ask > max_sl_price) 
                {
                    Print("spełniony warunek, przekroczyliśmy stratę z sell'a, powinno zamknąć");
                    if(g_Trade.PositionClose(ticket))                             
                        Print("Pozycja " + IntegerToString(ticket) + " zamknięta gdyż na pozycji jest za duża strata");     
                    else
                        Print("Błąd zamykania pozycji: ", GetLastError());
                }
            }
            
            Print("max sl price: " + DoubleToString(max_sl_price, 5));
        }
    }
}

#endif // POSITIONMANAGER_MQH
