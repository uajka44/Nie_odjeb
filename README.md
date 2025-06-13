# EA Nie_odjeb - Opis struktury projektu

## Przegląd
Program został podzielony na modularne komponenty dla lepszej czytelności i łatwości utrzymania kodu.

## Struktura plików

### Główny plik
- **Nie_odjeb.mq5** - Główny plik Expert Advisor zawierający funkcje OnInit(), OnDeinit(), OnTimer(), OnChartEvent() i OnTradeTransaction()

### Moduły Include

#### 1. **Config.mqh** - Konfiguracja
**Zawiera:**
- Wszystkie parametry wejściowe EA (input variables)
- Tablicę ustawień instrumentów
- Funkcje inicjalizacji ustawień instrumentów
- Gettery do pobierania parametrów konfiguracyjnych
- Funkcje do pobierania ustawień dla konkretnych symboli

**Główne funkcje:**
- `Config_InitializeInstrumentSettings()` - inicjalizacja ustawień dla wszystkich instrumentów
- `Config_GetInstrumentSettings()` - pobieranie ustawień dla danego symbolu
- `Config_GetDefaultSLForSymbol()` - pobieranie domyślnego SL dla symbolu
- `Config_GetMaxSLForSymbol()` - pobieranie maksymalnego SL dla symbolu
- Różne gettery dla parametrów konfiguracyjnych

#### 2. **DataStructures.mqh** - Struktury danych
**Zawiera:**
- `ClosedPosition` - struktura przechowująca informacje o zamkniętych pozycjach
- `InstrumentSettings` - struktura ustawień instrumentu (symbol, wolumen, stop lossy)

#### 3. **DatabaseManager.mqh** - Zarządzanie bazą danych
**Zawiera:**
- Funkcje do obsługi natywnej bazy SQLite
- Eksport świeczek do bazy danych
- Inicjalizacja i zamykanie połączenia z bazą

**Główne funkcje:**
- `DatabaseManager_Init()` - inicjalizacja bazy danych
- `DatabaseManager_Deinit()` - zamknięcie bazy danych
- `DatabaseManager_ExportCandles()` - eksport świeczek (klawisz 'j')
- `DatabaseManager_SaveCandleData()` - zapis pojedynczej świeczki
- `DatabaseManager_ProcessSymbol()` - przetwarzanie symbolu przy eksporcie

#### 4. **BreakManager.mqh** - Zarządzanie przerwami
**Zawiera:**
- Logikę zarządzania przerwami w tradingu
- Sprawdzanie dziennych limitów strat
- Analizę serii stratnych pozycji
- Obsługę czasowych blokad tradingu

**Główne funkcje:**
- `BreakManager_Init()` - inicjalizacja zarządzania przerwami
- `BreakManager_CheckDailyLimits()` - sprawdzenie dziennych limitów
- `BreakManager_GetLastClosedPositions()` - pobieranie ostatnich zamkniętych pozycji
- `BreakManager_CheckLossStreak()` - sprawdzenie serii strat
- `BreakManager_CanTrade()` - sprawdzenie czy można tradować
- `BreakManager_HandleClosedPosition()` - obsługa zamkniętej pozycji
- `BreakManager_SaveDateToCSV()` - zapis daty przerwy do CSV

#### 5. **VolumeManager.mqh** - Zarządzanie wolumenem
**Zawiera:**
- Dostosowywanie wolumenu do wielkości stop loss
- Sprawdzanie i modyfikacja stop loss dla oczekujących zleceń
- Logikę przeliczania optymalnego wolumenu

**Główne funkcje:**
- `VolumeManager_AdjustVolToSL()` - dostosowanie wolumenu do SL
- `VolumeManager_CheckOrderStopLoss()` - sprawdzenie SL dla zleceń

#### 6. **PositionManager.mqh** - Zarządzanie pozycjami
**Zawiera:**
- Sprawdzanie i modyfikacja stop loss dla otwartych pozycji
- Zamykanie pozycji przy przekroczeniu maksymalnej straty
- Monitorowanie wszystkich pozycji

**Główne funkcje:**
- `PositionManager_Init()` - inicjalizacja zarządzania pozycjami
- `PositionManager_CheckPositionStopLoss()` - sprawdzenie SL dla pozycji
- `PositionManager_CheckAllPositions()` - sprawdzenie wszystkich pozycji
- `PositionManager_CheckAllPositionsForMaxLoss()` - sprawdzenie pozycji pod kątem maksymalnej straty

## Przepływ działania programu

### Inicjalizacja (OnInit)
1. Inicjalizacja bazy danych (DatabaseManager)
2. Inicjalizacja ustawień instrumentów (Config)
3. Inicjalizacja zarządzania przerwami (BreakManager)
4. Inicjalizacja zarządzania pozycjami (PositionManager)
5. Ustawienie timera

### Timer (OnTimer)
- Sprawdzanie wszystkich pozycji pod kątem maksymalnej straty

### Zdarzenia klawiatury (OnChartEvent)
- Klawisz 'j': Eksport świeczek do bazy danych

### Transakcje (OnTradeTransaction)
- Obsługa zamkniętych pozycji (zarządzanie przerwami)
- Sprawdzanie i modyfikacja stop loss
- Dostosowywanie wolumenu

## Główne funkcjonalności

### 1. Zarządzanie przerwami w tradingu
- Przerwa po 2 stratnych pozycjach z rzędu (domyślnie 3 minuty)
- Przerwa po 3 stratnych pozycjach z rzędu (domyślnie 6 minut)
- Dzienny limit strat (domyślnie 55.0)
- Zapis informacji o przerwie do pliku CSV

### 2. Dostosowywanie wolumenu
- Automatyczne przeliczanie wolumenu na podstawie wielkości stop loss
- Utrzymanie stałego ryzyka na pozycję
- Respektowanie minimalnych i maksymalnych wolumenów dla instrumentu

### 3. Zarządzanie stop loss
- Automatyczne ustawianie maksymalnego stop loss dla pozycji bez SL
- Ograniczanie stop loss do maksymalnych wartości dla każdego instrumentu
- Zamykanie pozycji przy przekroczeniu maksymalnej straty

### 4. Eksport danych
- Eksport świeczek minutowych do bazy SQLite
- Obsługa wielu instrumentów jednocześnie
- Incremental update (tylko nowe dane)

## Konfiguracja instrumentów

Program obsługuje następujące instrumenty z predefiniowanymi ustawieniami:
- **BTCUSD**: Volume=1, Default SL=50, Max SL=100
- **US30.cash**: Volume=default_vol_dj, Default SL=20, Max SL=40
- **[DJI30]-Z**: Volume=default_vol_dj, Default SL=20, Max SL=40
- **US100.cash**: Volume=default_vol_nq, Default SL=10, Max SL=20
- **GER40.cash**: Volume=default_vol_dax, Default SL=10, Max SL=20

## Zalety modularnej struktury

1. **Czytelność**: Każdy moduł ma jasno określoną odpowiedzialność
2. **Łatwość utrzymania**: Zmiany w jednej funkcjonalności nie wpływają na inne
3. **Testowanie**: Każdy moduł można testować niezależnie
4. **Rozszerzalność**: Łatwo dodać nowe funkcjonalności
5. **Ponowne użycie**: Moduły można wykorzystać w innych projektach

## Pliki wygenerowane przez EA
- **multi_candles.db**: Baza danych SQLite ze świeczkami
- **przerwa_do.csv**: Plik z informacją o czasie końca przerwy w tradingu

## Uwagi techniczne
- Program wykorzystuje natywną obsługę SQLite w MetaTrader 5
- Wszystkie funkcje są poprzedzone prefiksem nazwy modułu dla uniknięcia konfliktów
- Używane są globalne zmienne z prefiksem g_ dla jasnego oznaczenia zasięgu
- Include guards (#ifndef/#define/#endif) zapobiegają wielokrotnemu dołączaniu plików
