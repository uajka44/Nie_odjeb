//+------------------------------------------------------------------+
//|                                              VolumeManager.mqh |
//|                   Zarządzanie wolumenem dla EA Nie_odjeb         |
//+------------------------------------------------------------------+

#ifndef VOLUMEMANAGER_MQH
#define VOLUMEMANAGER_MQH

#include "Config.mqh"
#include <Trade\Trade.mqh>

// Globalna instancja CTrade
CTrade g_Trade;

//+------------------------------------------------------------------+
//| Dostosowanie wolumenu do stop loss                               |
//+------------------------------------------------------------------+
void VolumeManager_AdjustVolToSL()
{
    int totalOrders = OrdersTotal();
    
    for(int i = totalOrders - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        
        if(ticket > 0)
        {
            string symbol = OrderGetString(ORDER_SYMBOL);
            double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            double stopLoss = OrderGetDouble(ORDER_SL);
            double takeProfit = OrderGetDouble(ORDER_TP);
            double volume = OrderGetDouble(ORDER_VOLUME_INITIAL);
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            
            // Pobierz ustawienia dla danego instrumentu
            double default_volume, default_stop_loss;
            int max_stop_loss;
            bool instrumentFound = Config_GetInstrumentSettings(symbol, default_volume, default_stop_loss, max_stop_loss);
            
            Print("Przetwarzam zlecenie dla ", symbol, " (Default SL=", default_stop_loss, 
                  ", Max SL=", max_stop_loss, ", Volume=", default_volume, ")");
            
            // Sprawdź czy to jest oczekujące zlecenie
            if(orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT)
            {
                // Najpierw sprawdź, czy stop loss nie jest zbyt duży
                VolumeManager_CheckOrderStopLoss(ticket);
                
                // Następnie sprawdź, czy volume jest poprawne w stosunku do obecnego SL
                double stopLossPoints = 0;
                
                if(stopLoss != 0)
                {
                    if(orderType == ORDER_TYPE_BUY_LIMIT)
                        stopLossPoints = (openPrice - stopLoss);
                    else
                        stopLossPoints = (stopLoss - openPrice);
                    
                    Print("Stop loss points: " + DoubleToString(stopLossPoints, 5));
                    
                    if(stopLossPoints != default_stop_loss)
                    {
                        Print("***** Stop loss zmieniony, działamy!");
                        
                        // Oblicz nowy wolumen
                        Print("Default stop loss: " + DoubleToString(default_stop_loss, 5));
                        Print("Stoploss points: " + DoubleToString(stopLossPoints, 5));
                        Print("Default volume: " + DoubleToString(default_volume, 5));
                        double newVolume = (default_stop_loss / stopLossPoints) * default_volume;
                        
                        // Zaokrąglij wolumen do dokładności lotu dla danego symbolu
                        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
                        newVolume = NormalizeDouble(MathFloor(newVolume / lotStep) * lotStep, 2);
                        
                        if(volume != newVolume)
                        {
                            Print("wolumen różny, zmieniamy");
                            
                            // Sprawdź minimalny i maksymalny wolumen
                            double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
                            double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
                            
                            if(newVolume < minVolume) newVolume = minVolume;
                            if(newVolume > maxVolume) newVolume = maxVolume;
                            
                            Print("Zlecenie #", ticket, ": Zmiana wolumenu z ", volume, " na ", newVolume);
                            
                            // Usuń stare zlecenie i dodaj nowe ze zmienionym wolumenem
                            if(g_Trade.OrderDelete(ticket))
                            {
                                bool result = false;
                                
                                if(orderType == ORDER_TYPE_BUY_LIMIT)
                                    result = g_Trade.BuyLimit(newVolume, openPrice, symbol, stopLoss, takeProfit);
                                else if(orderType == ORDER_TYPE_SELL_LIMIT)
                                    result = g_Trade.SellLimit(newVolume, openPrice, symbol, stopLoss, takeProfit);
                                    
                                if(result)
                                    Print("Utworzono nowe zlecenie dla ", symbol, " z wolumenem ", newVolume);
                                else
                                    Print("Błąd przy tworzeniu nowego zlecenia: ", GetLastError());
                            }
                            else
                            {
                                Print("Błąd przy usuwaniu zlecenia #", ticket, ": ", GetLastError());
                            }
                        }
                        else 
                        {
                            Print("wolumen ten sam, nie zmieniamy");
                        }
                    }
                    else 
                    {
                        Print("Mamy default stop loss, nic nie robimy");
                    }
                }
                else
                {
                    Print("Zlecenie #", ticket, " nie ma ustawionego stop loss, pomijam");
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Sprawdzenie i modyfikacja stop loss dla oczekujących zleceń      |
//+------------------------------------------------------------------+
void VolumeManager_CheckOrderStopLoss(ulong ticket)
{
    if(OrderSelect(ticket))
    {
        double order_price_open = OrderGetDouble(ORDER_PRICE_OPEN);
        double order_stop_loss_price = OrderGetDouble(ORDER_SL);
        string order_symbol = OrderGetString(ORDER_SYMBOL);
              
        // Pobierz maksymalny stop loss dla danego symbolu
        double max_sl_points = Config_GetMaxSLForSymbol(order_symbol);
             
        double max_sl_price = 0;
             
        // Oblicz odległość stop loss
        double order_stop_loss_distance = MathAbs(order_price_open - order_stop_loss_price);
        Print(" odległość SL orderu ", ticket, " wynosi ", order_stop_loss_distance, " buy/sell: ", OrderGetInteger(ORDER_TYPE));
             
        if(order_stop_loss_distance > max_sl_points)   // jeśli za duży sl dla oczekującego
        {  
            if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) // buy
                max_sl_price = order_price_open - max_sl_points;  
            else if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)   // sell
                max_sl_price = order_price_open + max_sl_points;              
    
            if(g_Trade.OrderModify(ticket, order_price_open, max_sl_price, OrderGetDouble(ORDER_TP), ORDER_TIME_GTC, 0)) 
            {
                Print("order modify stop loss ponieważ stop loss za duży ", order_stop_loss_distance, ", symbol: ", order_symbol, ", max SL: ", max_sl_points);
            }      
        }
    }
}

#endif // VOLUMEMANAGER_MQH
