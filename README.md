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

#### 5. **VolumeManager.mqh - Zarządzanie wolumenem** (PRZEPISANY)
**Zawiera:**
- **NOWY SYSTEM**: Dostosowywanie wolumenu na podstawie referencji pierwszego zlecenia
- **Inteligentne wykrywanie**: Reaguje tylko na rzeczywiste modyfikacje stop lossa
- **Zabezpieczenie przed zapętleniem**: Cooldown i ignorowanie własnych modyfikacji
- **Pamięć referencyjna**: Zapamiętuje pierwsze ustawienia jako bazę obliczeń
- Sprawdzanie maksymalnego stop lossa dla oczekujących zleceń

**Główne funkcje:**
- `VolumeManager_Init()` - inicjalizacja nowego systemu
- `VolumeManager_HandleStopLossChange()` - główna obsługa zmian SL
- `VolumeManager_IsStopLossModification()` - wykrywanie rzeczywistych zmian SL
- `VolumeManager_FindOrCreateReference()` - zarządzanie referencjami zleceń
- `VolumeManager_ReplaceOrder()` - bezpieczna zamiana zlecenia z nowym wolumenem
- `VolumeManager_CleanupReferences()` - czyszczenie nieaktywnych referencji
- `VolumeManager_PrintReferencesStatus()` - debug i monitoring referencji

**NOWA LOGIKA DZIAŁANIA:**
1. **Przy pierwszej modyfikacji SL**: System zapamiętuje oryginalny wolumen i odległość SL jako "punkt bazowy"
2. **Przy kolejnych zmianach SL**: Oblicza nowy wolumen według proporcji: `nowy_volume = (oryginalna_odległość_SL / nowa_odległość_SL) * oryginalny_volume`
3. **Stała strata**: Niezależnie od pozycji SL, strata zawsze pozostaje taka sama
4. **Przykład**: Start 1.0 lot @ 10 pkt SL → zmiana na 20 pkt SL → automatycznie 0.5 lot (strata identyczna)

**ZABEZPIECZENIA:**
- 3-sekundowy cooldown po każdej modyfikacji zapobiega zapętleniu
- Ignorowanie zdarzeń pochodzących z własnych modyfikacji systemu
- Weryfikacja czy to rzeczywiście zmiana SL (nie ceny czy TP)
- Automatyczne czyszczenie referencji nieistniejących zleceń

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
- Klawisz 'p': Wyświetl statystyki pozycji w bazie danych
- Klawisz 'm': Ręczne sprawdzenie i zapis brakujących pozycji
- **NOWY** Klawisz 'g': Pokaż edytowaną pozycję na wykresie (integracja z dziennikiem Python)

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
- **NOWE: Automatyczny zapis zamkniętych pozycji do bazy danych**
- **NOWE: Śledzenie stop loss w momencie wypełniania limitów**
- **NOWE: Kolumna 'sl_recznie' przechowuje SL (jako cenę) z momentów otwarcia pozycji z limitów**
- Obsługa wielu instrumentów jednocześnie
- Incremental update (tylko nowe dane)
- Sprawdzanie i uzupełnianie pominiętych pozycji

### 5. **NOWE: Integracja z dziennikiem Python**
- **Klawisz 'G'**: Przechodzi do wykresu aktualnie edytowanej pozycji w dzienniku Python
- Odczyt ticket z pliku komunikacyjnego `E:\Trading\current_edit_ticket.txt`
- Automatyczne przełączanie na właściwy wykres symbolu
- Obsługa zarówno otwartych jak i zamkniętych pozycji
- Wyświetlanie szczegółów pozycji w konsoli
- Dodawanie komentarza na wykresie z informacją o edytowanej pozycji

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
- **multi_candles.db**: Baza danych SQLite ze świeczkami i pozycjami
  - Tabele dla świeczek: `[SYMBOL]` (np. `BTCUSD`, `US30.cash`)
  - **NOWA TABELA: `positions`** - zamknięte pozycje z pełnymi danymi
    - Zawiera wszystkie szczegóły pozycji: czas otwarcia/zamknięcia, ceny, SL/TP, commission, swap, profit
    - **Kolumna `sl_recznie`**: przechowuje stop loss z momentów ustawiania zleceń limit
- **przerwa_do.csv**: Plik z informacją o czasie końca przerwy w tradingu

## Uwagi techniczne
- Program wykorzystuje natywną obsługę SQLite w MetaTrader 5
- Wszystkie funkcje są poprzedzone prefiksem nazwy modułu dla uniknięcia konfliktów
- Używane są globalne zmienne z prefiksem g_ dla jasnego oznaczenia zasięgu
- Include guards (#ifndef/#define/#endif) zapobiegają wielokrotnemu dołączaniu plików
- **WYDAJNOŚĆ**: Funkcje zapisu pozycji są zoptymalizowane - sprawdzają tylko nowe pozycje i nie powielają już zapisanych

## Instrukcje obsługi nowych funkcji pozycji

1. **Automatyczny zapis pozycji**: Działa automatycznie przy każdym zamknięciu pozycji
2. **Śledzenie SL z limitów**: 
   - Ustaw zlecenie limit z stop loss
   - Możesz modyfikować SL aż do momentu wypełnienia zlecenia
   - **W momencie wypełnienia pozycji limit** program automatycznie zapamięta aktualny SL
   - Po zamknięciu pozycji SL zostanie zapisany w kolumnie `sl_recznie` (jako cena)
3. **Ręczne sprawdzenie pozycji** (klawisz 'M'): Użyj gdy podejrzewasz, że jakieś pozycje nie zostały zapisane
4. **Statystyki** (klawisz 'P'): Wyświetla liczbę pozycji w bazie i ostatnie 3 transakcje
5. **NOWE: Przejście do edytowanej pozycji** (klawisz 'G'):
   - Upewnij się, że dziennik Python jest uruchomiony
   - Otwórz pozycję do edycji w dzienniku (podwójne kliknięcie)
   - W MetaTrader naciśnij klawisz 'G'
   - Program automatycznie przejdzie do wykresu edytowanej pozycji
   - Jeśli wykres nie jest otwarty, zostaniesz poinformowany o konieczności jego otwarcia
6. **NOWE: Volume Manager Debug** (klawisz 'V'):
   - Wyświetla status wszystkich aktywnych referencji zleceń
   - Pokazuje oryginalne i aktualne parametry volume/SL
   - Czyści nieaktywne referencje
   - Przydatne do debugowania problemu z wolumenem
7. **NOWE: Automatyczne zarządzanie wolumenem**:
   - **Pierwsza modyfikacja SL**: System zapamiętuje jako punkt bazowy
   - **Kolejne zmiany**: Automatyczne przeliczanie wolumenu (stała strata)
   - **Przykład**: 1 lot @ 10 pkt SL → zmiana na 5 pkt SL → automatycznie 2 loty
   - **Zabezpieczenia**: 3-sekundowy cooldown zapobiega zapętleniu
8. **Optymalizacja**: Program sprawdza tylko pozycje nowsze niż ostatnia w bazie (incremental update)

## NOWE: Instrukcje Volume Manager

### Jak korzystać z nowego systemu zarządzania wolumenem:

1. **Ustaw pierwsze zlecenie** w dowolnym oknie (może być inny EA lub ręcznie)
   - Przykład: 1.5 lot z SL 10 punktów
   
2. **Przenieś stop loss** - system automatycznie dostosuje wolumen:
   - SL na 20 pkt → wolumen zmieni się na 0.75 lot (strata identyczna)
   - SL na 5 pkt → wolumen zmieni się na 3.0 lot (strata identyczna)
   
3. **Monitoring**: Użyj klawisza 'V' aby zobaczyć aktywne referencje

4. **Debugging**: Obserwuj logi w konsoli - każda operacja jest dokładnie logowana

### Uwagi dotyczące nowego systemu:
- ✅ **Działa**: Tylko z oczekującymi zleceniami LIMIT (nie MARKET)
- ✅ **Elastyczność**: Pierwszy volume może być ustawiony w dowolny sposób
- ✅ **Bezpieczeństwo**: System ma zabezpieczenia przed zapętleniem
- ⚠️ **Ograniczenia**: Respektuje min/max volume dla każdego symbolu
- 🔄 **Restart**: Po restarcie MT5 system zapomina referencje (zgodnie z wymaganiami)
3. **Ręczne sprawdzenie pozycji** (klawisz 'M'): Użyj gdy podejrzewasz, że jakieś pozycje nie zostały zapisane
4. **Statystyki** (klawisz 'P'): Wyświetla liczbę pozycji w bazie i ostatnie 3 transakcje
5. **NOWE: Przejście do edytowanej pozycji** (klawisz 'G'):
   - Upewnij się, że dziennik Python jest uruchomiony
   - Otwórz pozycję do edycji w dzienniku (podwójne kliknięcie)
   - W MetaTrader naciśnij klawisz 'G'
   - Program automatycznie przejdzie do wykresu edytowanej pozycji
   - Jeśli wykres nie jest otwarty, zostaniesz poinformowany o konieczności jego otwarcia
6. **Optymalizacja**: Program sprawdza tylko pozycje nowsze niż ostatnia w bazie (incremental update)
