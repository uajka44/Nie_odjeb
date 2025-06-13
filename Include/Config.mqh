//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|                          Konfiguracja EA Nie_odjeb               |
//+------------------------------------------------------------------+

#ifndef CONFIG_MQH
#define CONFIG_MQH

#include "DataStructures.mqh"

// Parametry wejściowe EA
input double MaxDailyLoss = 55.0;        // Maksymalna dzienna strata
input int max_sl_unknown = 15;           // Domyślny SL dla nieznanych instrumentów
input int timerInterval = 30;            // Co ile sekund wywołuje OnTimer
input int przerwa_2stratne = 3;          // Przerwa w minutach po 2 stratnych z rzędu
input int przerwa_3stratne = 6;          // Przerwa w minutach po 3 stratnych z rzędu
input double default_vol_dax = 1;        // Domyślny wolumen dla DAX
input double default_vol_dj = 1;         // Domyślny wolumen dla DJ
input double default_vol_nq = 1;         // Domyślny wolumen dla NQ
input bool zmiana_vol = true;            // Czy zmieniać wielkość pozycji

// Parametry eksportu świeczek
input string Symbols = "US30.cash,GER40.cash"; // Symbole do eksportu świeczek
input datetime StartDate = D'2025.06.01 00:00'; // Data początkowa eksportu

// Inne parametry
int przesuniecie_czasu_platforma_warszawa = 7200;

// Globalna tablica ustawień instrumentów
InstrumentSettings g_instrumentArray[];

//+------------------------------------------------------------------+
//| Inicjalizacja ustawień instrumentów                              |
//+------------------------------------------------------------------+
bool Config_InitializeInstrumentSettings()
{
    // Określ liczbę instrumentów
    int instrumentCount = 5;
    
    // Zainicjuj tablicę
    ArrayResize(g_instrumentArray, instrumentCount);
    
    // Ustaw wartości dla każdego instrumentu
    g_instrumentArray[0].symbol = "BTCUSD";
    g_instrumentArray[0].default_volume = 1;
    g_instrumentArray[0].default_stop_loss = 50;
    g_instrumentArray[0].max_stop_loss = 100;
    
    g_instrumentArray[1].symbol = "US30.cash";
    g_instrumentArray[1].default_volume = default_vol_dj;
    g_instrumentArray[1].default_stop_loss = 20;
    g_instrumentArray[1].max_stop_loss = 40;
    
    g_instrumentArray[2].symbol = "[DJI30]-Z";
    g_instrumentArray[2].default_volume = default_vol_dj;
    g_instrumentArray[2].default_stop_loss = 20;
    g_instrumentArray[2].max_stop_loss = 40;
    
    g_instrumentArray[3].symbol = "US100.cash";
    g_instrumentArray[3].default_volume = default_vol_nq;
    g_instrumentArray[3].default_stop_loss = 10;
    g_instrumentArray[3].max_stop_loss = 20;
    
    g_instrumentArray[4].symbol = "GER40.cash";
    g_instrumentArray[4].default_volume = default_vol_dax;
    g_instrumentArray[4].default_stop_loss = 10;
    g_instrumentArray[4].max_stop_loss = 20;
    
    // Wypisz zainicjowane wartości
    for(int i = 0; i < instrumentCount; i++)
    {
        Print("Zainicjowano ustawienia dla ", g_instrumentArray[i].symbol, 
              ": Volume=", g_instrumentArray[i].default_volume, 
              ", Default Stop Loss=", g_instrumentArray[i].default_stop_loss,
              ", Max Stop Loss=", g_instrumentArray[i].max_stop_loss);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Pobierz ustawienia dla danego instrumentu                        |
//+------------------------------------------------------------------+
bool Config_GetInstrumentSettings(const string symbol, double &volume, double &stop_loss, int &max_stop_loss)
{
    int size = ArraySize(g_instrumentArray);
    
    for(int i = 0; i < size; i++)
    {
        if(StringFind(symbol, g_instrumentArray[i].symbol) >= 0)
        {
            volume = g_instrumentArray[i].default_volume;
            stop_loss = g_instrumentArray[i].default_stop_loss;
            max_stop_loss = g_instrumentArray[i].max_stop_loss;
            return true;
        }
    }
    
    // Jeśli nie znaleziono, ustaw domyślne wartości
    volume = 1;
    stop_loss = max_sl_unknown;
    max_stop_loss = max_sl_unknown;
    return false;
}

//+------------------------------------------------------------------+
//| Pobierz domyślny stop loss dla symbolu                           |
//+------------------------------------------------------------------+
double Config_GetDefaultSLForSymbol(string symbol)
{
    for(int i = 0; i < ArraySize(g_instrumentArray); i++)
    {
        if(g_instrumentArray[i].symbol == symbol)
        {
            return g_instrumentArray[i].default_stop_loss;
        }
    }
    
    Print("Nie znaleziono przelicznika dla symbolu: ", symbol, ". Używam domyślnego");
    return 10.0;
}

//+------------------------------------------------------------------+
//| Pobierz maksymalny stop loss dla symbolu                         |
//+------------------------------------------------------------------+
int Config_GetMaxSLForSymbol(string symbol)
{
    double volume, stop_loss;
    int max_stop_loss;
    
    Config_GetInstrumentSettings(symbol, volume, stop_loss, max_stop_loss);
    return max_stop_loss;
}

//+------------------------------------------------------------------+
//| Gettery dla parametrów konfiguracyjnych                          |
//+------------------------------------------------------------------+
double Config_GetMaxDailyLoss() { return MaxDailyLoss; }
int Config_GetTimerInterval() { return timerInterval; }
int Config_GetBreak2Losses() { return przerwa_2stratne; }
int Config_GetBreak3Losses() { return przerwa_3stratne; }
bool Config_GetChangeVolume() { return zmiana_vol; }
string Config_GetSymbols() { return Symbols; }
datetime Config_GetStartDate() { return StartDate; }

#endif // CONFIG_MQH
