//+------------------------------------------------------------------+
//|                                              VolumeManager.mqh |
//|                   Zarządzanie wolumenem dla EA Nie_odjeb         |
//|                          NOWA WERSJA - Reaguje na modyfikacje SL |
//+------------------------------------------------------------------+

#ifndef VOLUMEMANAGER_MQH
#define VOLUMEMANAGER_MQH

#include "Config.mqh"
#include <Trade\Trade.mqh>

// Globalna instancja CTrade
CTrade g_Trade;

//+------------------------------------------------------------------+
//| DEKLARACJE FUNKCJI - NOWY SYSTEM                                 |
//+------------------------------------------------------------------+
void VolumeManager_Init();
bool VolumeManager_IsStopLossModification(ulong ticket);
void VolumeManager_HandleStopLossChange(ulong ticket);
void VolumeManager_CleanupReferences();
void VolumeManager_PrintReferencesStatus();

//+------------------------------------------------------------------+
//| Struktura do przechowywania danych referencyjnych zlecenia       |
//+------------------------------------------------------------------+
struct OrderReference
{
    ulong ticket;                    // Numer zlecenia
    double original_volume;          // Oryginalny wolumen (pierwszy)
    double original_sl_distance;    // Oryginalna odległość SL w punktach
    double last_sl_distance;        // Ostatnia znana odległość SL
    datetime created_time;           // Kiedy utworzono referencję
    datetime last_modification;     // Ostatnia modyfikacja
    string symbol;                   // Symbol zlecenia
    double open_price;              // Cena otwarcia zlecenia
    ENUM_ORDER_TYPE order_type;    // Typ zlecenia
    bool is_managed;                // Czy zlecenie jest zarządzane przez nas
};

// Globalna tablica referencji zleceń
OrderReference g_orderReferences[];

// Globalne zmienne dla zabezpieczenia przed zapętleniem
datetime g_lastVolumeModification = 0;
ulong g_lastModifiedTicket = 0;
const int MODIFICATION_COOLDOWN = 3; // Sekundy przerwy po modyfikacji

//+------------------------------------------------------------------+
//| Inicjalizacja VolumeManager                                      |
//+------------------------------------------------------------------+
void VolumeManager_Init()
{
    ArrayResize(g_orderReferences, 0);
    g_lastVolumeModification = 0;
    g_lastModifiedTicket = 0;
    Print("[VOLUME] VolumeManager zainicjalizowany - nowy system referencyjny");
}

//+------------------------------------------------------------------+
//| Sprawdź czy to modyfikacja stop lossa (nie inne zmiany)          |
//+------------------------------------------------------------------+
bool VolumeManager_IsStopLossModification(ulong ticket)
{
    if(!OrderSelect(ticket))
        return false;
        
    // Sprawdź czy to oczekujące zlecenie limit
    ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT)
        return false;
        
    // Sprawdź czy zlecenie ma SL
    double currentSL = OrderGetDouble(ORDER_SL);
    if(currentSL == 0)
        return false;
        
    // Sprawdź czy to nie nasze własne zlecenie (zabezpieczenie przed zapętleniem)
    datetime currentTime = TimeCurrent();
    if(ticket == g_lastModifiedTicket && 
       currentTime - g_lastVolumeModification < MODIFICATION_COOLDOWN)
    {
        Print("[VOLUME] 🛡️ Ignoruję własną modyfikację ticket ", ticket, 
              " (cooldown ", (currentTime - g_lastVolumeModification), "s)");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Główna funkcja obsługi zmiany stop lossa                         |
//+------------------------------------------------------------------+
void VolumeManager_HandleStopLossChange(ulong ticket)
{
    if(!Config_GetChangeVolume())
    {
        Print("[VOLUME] ⚠️ Zmiana wolumenu wyłączona w konfiguracji");
        return;
    }
    
    if(!VolumeManager_IsStopLossModification(ticket))
        return;
        
    if(!OrderSelect(ticket))
    {
        Print("[VOLUME] ❌ Nie można wybrać zlecenia ", ticket);
        return;
    }
    
    // Pobierz dane zlecenia
    string symbol = OrderGetString(ORDER_SYMBOL);
    double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);
    double currentSL = OrderGetDouble(ORDER_SL);
    double currentTP = OrderGetDouble(ORDER_TP);
    double currentVolume = OrderGetDouble(ORDER_VOLUME_INITIAL);
    ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    
    // Oblicz aktualną odległość SL w punktach
    double currentSLDistance = 0;
    if(orderType == ORDER_TYPE_BUY_LIMIT)
        currentSLDistance = openPrice - currentSL;
    else if(orderType == ORDER_TYPE_SELL_LIMIT)
        currentSLDistance = currentSL - openPrice;
        
    Print("[VOLUME] 📊 Ticket ", ticket, " (", symbol, "): SL zmieniony na ", 
          DoubleToString(currentSLDistance, 5), " pkt, volume=", currentVolume);
    
    // Znajdź lub utwórz referencję dla tego zlecenia
    int refIndex = VolumeManager_FindOrCreateReference(ticket, symbol, openPrice, 
                                                       currentVolume, currentSLDistance, orderType);
                                                       
    if(refIndex < 0)
    {
        Print("[VOLUME] ❌ Nie udało się utworzyć referencji dla ticket ", ticket);
        return;
    }
    
    OrderReference ref = g_orderReferences[refIndex];
    
    // Sprawdź czy SL rzeczywiście się zmienił
    if(MathAbs(currentSLDistance - ref.last_sl_distance) < 0.00001)
    {
        Print("[VOLUME] 📌 SL nie zmienił się znacząco (", 
              DoubleToString(ref.last_sl_distance, 5), " vs ", 
              DoubleToString(currentSLDistance, 5), ")");
        return;
    }
    
    // Oblicz nowy wolumen na podstawie proporcji
    double newVolume = (ref.original_sl_distance / currentSLDistance) * ref.original_volume;
    
    Print("[VOLUME] 🧮 Obliczenia:");
    Print("[VOLUME]   Oryginalny: ", ref.original_volume, " lot @ ", ref.original_sl_distance, " pkt");
    Print("[VOLUME]   Aktualny: ", currentVolume, " lot @ ", currentSLDistance, " pkt");
    Print("[VOLUME]   Nowy obliczony: ", newVolume, " lot");
    
    // Normalizuj wolumen
    newVolume = VolumeManager_NormalizeVolume(newVolume, symbol);
    
    // Sprawdź czy wolumen rzeczywiście się zmienił
    if(MathAbs(newVolume - currentVolume) < 0.001)
    {
        Print("[VOLUME] ✅ Wolumen już jest poprawny (", newVolume, ")");
        g_orderReferences[refIndex].last_sl_distance = currentSLDistance;
        g_orderReferences[refIndex].last_modification = TimeCurrent();
        return;
    }
    
    Print("[VOLUME] 🔄 Zmieniam wolumen z ", currentVolume, " na ", newVolume);
    
    // Sprawdź maksymalny SL przed modyfikacją
    if(!VolumeManager_CheckMaxStopLoss(ticket, symbol, openPrice, currentSL, orderType))
    {
        Print("[VOLUME] ⚠️ SL zbyt duży - nie zmieniam wolumenu");
        return;
    }
    
    // Wykonaj zamianę zlecenia
    if(VolumeManager_ReplaceOrder(ticket, symbol, openPrice, newVolume, currentSL, currentTP, orderType))
    {
        // Aktualizuj referencję - w MQL5 trzeba przypisac calą strukturę
        g_orderReferences[refIndex].last_sl_distance = currentSLDistance;
        g_orderReferences[refIndex].last_modification = TimeCurrent();
        
        // Ustaw zabezpieczenie przeciw zapętleniu
        g_lastVolumeModification = TimeCurrent();
        g_lastModifiedTicket = ticket; // To będzie nowy ticket, ale dla bezpieczeństwa
        
        Print("[VOLUME] ✅ Pomyślnie zmieniono wolumen dla ", symbol);
    }
    else
    {
        Print("[VOLUME] ❌ Błąd przy zamianie zlecenia");
    }
}

//+------------------------------------------------------------------+
//| Znajdź lub utwórz referencję dla zlecenia                        |
//+------------------------------------------------------------------+
int VolumeManager_FindOrCreateReference(ulong ticket, string symbol, double openPrice,
                                        double volume, double slDistance, ENUM_ORDER_TYPE orderType)
{
    // Sprawdź czy referencja już istnieje
    int size = ArraySize(g_orderReferences);
    for(int i = 0; i < size; i++)
    {
        if(g_orderReferences[i].ticket == ticket)
        {
            Print("[VOLUME] 📎 Znaleziono istniejącą referencję dla ticket ", ticket, 
                  " (indeks ", i, ")");
            return i;
        }
    }
    
    // Utwórz nową referencję
    ArrayResize(g_orderReferences, size + 1);
    
    g_orderReferences[size].ticket = ticket;
    g_orderReferences[size].original_volume = volume;
    g_orderReferences[size].original_sl_distance = slDistance;
    g_orderReferences[size].last_sl_distance = slDistance;
    g_orderReferences[size].created_time = TimeCurrent();
    g_orderReferences[size].last_modification = TimeCurrent();
    g_orderReferences[size].symbol = symbol;
    g_orderReferences[size].open_price = openPrice;
    g_orderReferences[size].order_type = orderType;
    g_orderReferences[size].is_managed = true;
    
    Print("[VOLUME] ➕ Utworzono nową referencję [", size, "] dla ticket ", ticket);
    Print("[VOLUME]   Symbol: ", symbol, ", Volume: ", volume, ", SL: ", slDistance, " pkt");
    
    return size;
}

//+------------------------------------------------------------------+
//| Normalizuj wolumen zgodnie z wymaganiami symbolu                 |
//+------------------------------------------------------------------+
double VolumeManager_NormalizeVolume(double volume, string symbol)
{
    double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double stepVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    // Ograniczenia min/max
    if(volume < minVolume) 
    {
        Print("[VOLUME] ⚠️ Wolumen ", volume, " < minimum ", minVolume, " - ustawiam minimum");
        volume = minVolume;
    }
    if(volume > maxVolume) 
    {
        Print("[VOLUME] ⚠️ Wolumen ", volume, " > maksimum ", maxVolume, " - ustawiam maksimum");
        volume = maxVolume;
    }
    
    // Zaokrąglenie do kroku
    if(stepVolume > 0)
    {
        volume = MathFloor(volume / stepVolume) * stepVolume;
        volume = NormalizeDouble(volume, 2);
    }
    
    Print("[VOLUME] 🎯 Znormalizowany wolumen: ", volume, 
          " (min=", minVolume, ", max=", maxVolume, ", step=", stepVolume, ")");
    
    return volume;
}

//+------------------------------------------------------------------+
//| Sprawdź czy SL nie przekracza maksimum                           |
//+------------------------------------------------------------------+
bool VolumeManager_CheckMaxStopLoss(ulong ticket, string symbol, double openPrice, 
                                     double slPrice, ENUM_ORDER_TYPE orderType)
{
    double maxSLPoints = Config_GetMaxSLForSymbol(symbol);
    double currentSLDistance = MathAbs(openPrice - slPrice);
    
    if(currentSLDistance > maxSLPoints)
    {
        Print("[VOLUME] ⚠️ SL ", currentSLDistance, " > maksimum ", maxSLPoints, 
              " dla ", symbol, " - korekcja wymagana");
              
        // Oblicz poprawny SL
        double correctedSL;
        if(orderType == ORDER_TYPE_BUY_LIMIT)
            correctedSL = openPrice - maxSLPoints;
        else
            correctedSL = openPrice + maxSLPoints;
            
        // Modyfikuj SL do maksymalnej wartości
        if(g_Trade.OrderModify(ticket, openPrice, correctedSL, OrderGetDouble(ORDER_TP), ORDER_TIME_GTC, 0))
        {
            Print("[VOLUME] ✅ SL skorygowany z ", currentSLDistance, " do ", maxSLPoints, " pkt");
        }
        else
        {
            Print("[VOLUME] ❌ Błąd korekcji SL: ", GetLastError());
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Zamień zlecenie (usuń stare, utwórz nowe z nowym wolumenem)      |
//+------------------------------------------------------------------+
bool VolumeManager_ReplaceOrder(ulong oldTicket, string symbol, double openPrice, 
                                double newVolume, double slPrice, double tpPrice, 
                                ENUM_ORDER_TYPE orderType)
{
    Print("[VOLUME] 🔄 Zamieniam zlecenie ", oldTicket, ": ", symbol, 
          " - nowy wolumen ", newVolume);
    
    // Usuń stare zlecenie
    if(!g_Trade.OrderDelete(oldTicket))
    {
        Print("[VOLUME] ❌ Nie udało się usunąć zlecenia ", oldTicket, ": ", GetLastError());
        return false;
    }
    
    Print("[VOLUME] 🗑️ Usunięto stare zlecenie ", oldTicket);
    
    // Czekaj chwilę na przetworzenie
    Sleep(100);
    
    // Utwórz nowe zlecenie
    bool result = false;
    if(orderType == ORDER_TYPE_BUY_LIMIT)
    {
        result = g_Trade.BuyLimit(newVolume, openPrice, symbol, slPrice, tpPrice);
    }
    else if(orderType == ORDER_TYPE_SELL_LIMIT)
    {
        result = g_Trade.SellLimit(newVolume, openPrice, symbol, slPrice, tpPrice);
    }
    
    if(result)
    {
        ulong newTicket = g_Trade.ResultOrder();
        Print("[VOLUME] ✅ Utworzono nowe zlecenie ", newTicket, " z wolumenem ", newVolume);
        
        // Aktualizuj referencję na nowy ticket
        VolumeManager_UpdateReferenceTicket(oldTicket, newTicket);
        
        return true;
    }
    else
    {
        Print("[VOLUME] ❌ Błąd tworzenia nowego zlecenia: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Aktualizuj ticket w referencji (po zamianie zlecenia)            |
//+------------------------------------------------------------------+
void VolumeManager_UpdateReferenceTicket(ulong oldTicket, ulong newTicket)
{
    int size = ArraySize(g_orderReferences);
    for(int i = 0; i < size; i++)
    {
        if(g_orderReferences[i].ticket == oldTicket)
        {
            g_orderReferences[i].ticket = newTicket;
            Print("[VOLUME] 🔄 Zaktualizowano referencję: ", oldTicket, " → ", newTicket);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Wyczyść nieaktywne referencje (zlecenia już nie istnieją)        |
//+------------------------------------------------------------------+
void VolumeManager_CleanupReferences()
{
    int size = ArraySize(g_orderReferences);
    int removed = 0;
    
    for(int i = size - 1; i >= 0; i--)
    {
        ulong ticket = g_orderReferences[i].ticket;
        
        // Sprawdź czy zlecenie nadal istnieje
        if(!OrderSelect(ticket))
        {
            // Usuń referencję
            for(int j = i; j < size - 1; j++)
            {
                g_orderReferences[j] = g_orderReferences[j + 1];
            }
            ArrayResize(g_orderReferences, size - 1);
            size--;
            removed++;
            
            Print("[VOLUME] 🗑️ Usunięto referencję dla nieistniejącego zlecenia ", ticket);
        }
    }
    
    if(removed > 0)
    {
        Print("[VOLUME] 🧹 Wyczyszczono ", removed, " nieaktywnych referencji");
    }
}

//+------------------------------------------------------------------+
//| Pokaż status wszystkich referencji (debug)                       |
//+------------------------------------------------------------------+
void VolumeManager_PrintReferencesStatus()
{
    int size = ArraySize(g_orderReferences);
    
    Print("[VOLUME] 📋 Status referencji zleceń (", size, " aktywnych):");
    
    for(int i = 0; i < size; i++)
    {
        Print("[VOLUME] [", i, "] Ticket: ", g_orderReferences[i].ticket, 
              ", Symbol: ", g_orderReferences[i].symbol,
              ", Orig: ", g_orderReferences[i].original_volume, " @ ", g_orderReferences[i].original_sl_distance, " pkt",
              ", Last SL: ", g_orderReferences[i].last_sl_distance, " pkt",
              ", Created: ", TimeToString(g_orderReferences[i].created_time, TIME_SECONDS));
    }
    
    if(size == 0)
    {
        Print("[VOLUME] (Brak aktywnych referencji)");
    }
}

//+------------------------------------------------------------------+
//| STARE FUNKCJE - zachowane dla kompatybilności                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Dostosowanie wolumenu do stop loss - STARA FUNKCJA               |
//+------------------------------------------------------------------+
void VolumeManager_AdjustVolToSL()
{
    Print("[VOLUME] ⚠️ Wywołano starą funkcję VolumeManager_AdjustVolToSL()");
    Print("[VOLUME] 💡 Nowy system reaguje automatycznie na modyfikacje SL");
    
    // Opcjonalnie: wyczyść nieaktywne referencje
    VolumeManager_CleanupReferences();
    
    // Pokaż status (dla debugowania)
    VolumeManager_PrintReferencesStatus();
}

//+------------------------------------------------------------------+
//| Sprawdzenie i modyfikacja stop loss - STARA FUNKCJA             |
//+------------------------------------------------------------------+
void VolumeManager_CheckOrderStopLoss(ulong ticket)
{
    // Zachowujemy sprawdzanie maksymalnego SL (to jest nadal potrzebne)
    if(OrderSelect(ticket))
    {
        double order_price_open = OrderGetDouble(ORDER_PRICE_OPEN);
        double order_stop_loss_price = OrderGetDouble(ORDER_SL);
        string order_symbol = OrderGetString(ORDER_SYMBOL);
        ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
              
        // Pobierz maksymalny stop loss dla danego symbolu
        double max_sl_points = Config_GetMaxSLForSymbol(order_symbol);
             
        // Oblicz odległość stop loss
        double order_stop_loss_distance = MathAbs(order_price_open - order_stop_loss_price);
        Print("[VOLUME] 🔍 Sprawdzanie SL dla zlecenia ", ticket, ": ", 
              order_stop_loss_distance, " pkt (max: ", max_sl_points, ")");
             
        if(order_stop_loss_distance > max_sl_points)
        {  
            double max_sl_price = 0;
            if(order_type == ORDER_TYPE_BUY_LIMIT)
                max_sl_price = order_price_open - max_sl_points;  
            else if(order_type == ORDER_TYPE_SELL_LIMIT)
                max_sl_price = order_price_open + max_sl_points;              
    
            if(g_Trade.OrderModify(ticket, order_price_open, max_sl_price, OrderGetDouble(ORDER_TP), ORDER_TIME_GTC, 0)) 
            {
                Print("[VOLUME] ✅ Skorygowano SL z ", order_stop_loss_distance, 
                      " do ", max_sl_points, " pkt dla ", order_symbol);
            }
            else
            {
                Print("[VOLUME] ❌ Błąd korekcji SL: ", GetLastError());
            }
        }
    }
}

#endif // VOLUMEMANAGER_MQH