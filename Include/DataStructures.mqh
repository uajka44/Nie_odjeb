//+------------------------------------------------------------------+
//|                                              DataStructures.mqh |
//|                    Struktury danych dla EA Nie_odjeb             |
//+------------------------------------------------------------------+

#ifndef DATASTRUCTURES_MQH
#define DATASTRUCTURES_MQH

//+------------------------------------------------------------------+
//| Struktura do przechowywania informacji o zamkniętych pozycjach    |
//+------------------------------------------------------------------+
struct ClosedPosition
{
    string   symbol;        // Symbol instrumentu
    double   profit;        // Profit pozycji
    double   volume;        // Wolumen pozycji
    datetime closeTime;     // Czas zamknięcia
    double   ProfitPerUnit; // Profit na jednostkę wolumenu
};

//+------------------------------------------------------------------+
//| Struktura ustawień instrumentu                                   |
//+------------------------------------------------------------------+
struct InstrumentSettings
{
    string symbol;           // Nazwa instrumentu
    double default_volume;   // Domyślny wolumen
    double default_stop_loss; // Domyślny stop loss w punktach
    int max_stop_loss;       // Maksymalny stop loss
};

#endif // DATASTRUCTURES_MQH
