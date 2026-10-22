# iTgLegacy

Читать на других языках: [English](README.md)

Клиент Telegram, разработанный для старых устройств iOS под управлением iOS 6.0 – iOS 12.5.7.

Приложение использует гибридную архитектуру из двух движков: легкий движок на C для протокола MTProto (`libtg`) для старых 32-битных устройств и официальная библиотека Telegram Database Library (`tdlib`) для современных функций.

## Поддерживаемые устройства и архитектуры

Проект собирает как облегченные отдельные `.ipa` пакеты для каждой архитектуры, так и универсальный двойной бинарник:

- **armv7 (32-бит, ~8.8 МБ)**: Для устройств с iOS 6.0+ (iPhone 3GS, iPhone 4, iPhone 4S, iPhone 5, iPad 2/3/4, iPod Touch 4/5).
- **arm64 (64-бит, ~8.8 МБ)**: Для устройств с iOS 7.0 - 12.5.7 (iPhone 5s — iPhone X, iPad Air/Pro).
- **Универсальный (~16 МБ)**: Единый файл `iTgLegacy.ipa`, содержащий обе архитектуры.

## Настройка ключей Telegram API

Перед сборкой приложения для реального использования настройте ключи Telegram API:

1. Скопируйте шаблон [`include/tg_config.h.example`](include/tg_config.h.example) в `include/tg_config.h`:
   ```bash
   cp include/tg_config.h.example include/tg_config.h
   ```
2. Зарегистрируйте приложение на https://my.telegram.org (в разделе *API development tools*).
3. Вкажите свои `TG_API_ID` и `TG_API_HASH` в созданном файле `include/tg_config.h`:

```c
#define TG_API_ID   ВАШ_API_ID
#define TG_API_HASH "ВАШ_API_HASH"
```

> Примечание: файл `include/tg_config.h` добавлен в `.gitignore`, чтобы личные ключи никогда случайно не попали в репозиторий.

## Структура репозитория

```
iTgLegacy/
├── Makefile       # Главный файл сборки
├── README.md      # Документация (на английском)
├── README_RU.md   # Документация (на русском)
├── LICENSE        # Лицензия GPLv3
├── src/           # Исходные файлы приложения на Objective-C
│   ├── Core/      # Базовая логика, клиент, устройство
│   ├── Controllers/ # Контроллеры экранов (ViewControllers)
│   ├── Views/     # Кастомные UI-компоненты, ячейки, иконки
│   ├── Calls/     # Реализация VoIP и сквозного шифрования звонков
│   └── Audio/     # Запись и воспроизведение голосовых сообщений
├── resources/     # Ресурсы бандла (Info.plist, шрифты, entitlements)
├── images/        # Иконки и ресурсы приложения
├── third_party/   # Сторонние библиотеки (libtgvoip, opus, ogg и др.)
├── tdlib/         # Telegram Database Library (git submodule)
├── libs/          # Универсальные скомпилированные библиотеки и WebP.framework
├── include/       # Заголовочные файлы C и tg_config.h.example
├── compat/        # Полифиллы совместимости (dyld TLV, шимы iOS 7)
├── tools/         # Утилиты для хоста/устройства и твики
├── scripts/       # Скрипты автоматизации сборки и деплоя
├── tests/         # Модульные и интеграционные тесты
└── build/         # Результаты сборки (git-ignored)
    ├── iTgLegacy-armv7.ipa # 32-битный IPA для iOS 6.0+ (8.8 МБ)
    ├── iTgLegacy-arm64.ipa # 64-битный IPA для iOS 7.0-12.5.7 (8.8 МБ)
    └── iTgLegacy.ipa       # Универсальный IPA файл (16 МБ)
```

## Требования для сборки

Для сборки iTgLegacy на macOS необходимо:

1. Установленный Xcode с поддержкой iOS SDK.
2. Зависимости для сборки:
   ```bash
   brew install cmake gperf openssl@1.1 ccache
   ```

## Сборка

Склонируйте репозиторий вместе с подмодулями и запустите `make`:

```bash
git clone --recursive https://github.com/bla1r1/iTgLegacy.git
cd iTgLegacy
make
```

Или запустите скрипт сборки:

```bash
./scripts/build_ipa.sh
```

### Команды Makefile

- `make ipa` - Собрать все пакеты (`iTgLegacy-armv7.ipa`, `iTgLegacy-arm64.ipa` и универсальный `iTgLegacy.ipa`).
- `make ipa-armv7` - Собрать облегченный 32-битный `.ipa` (8.8 МБ для iOS 6.0+).
- `make ipa-arm64` - Собрать облегченный 64-битный `.ipa` (8.8 МБ для iOS 7.0 - 12.5.7).
- `make app` - Собрать только пакет `.app`.
- `make deps` - Подготовить статические библиотеки третьих сторон в `build/libs`.
- `make tdlib` - Скомпилировать TDLib для iOS.
- `make clean` - Удалить все промежуточные файлы из директории `build/`.

## Автор, история и лицензия

- **Автор и мейнтейнер**: [bla1r1](https://github.com/bla1r1)
- **Лицензия**: GNU General Public License v3.0 ([LICENSE](LICENSE))

### История происхождения кода
Изначально проект базировался на раннем прототипе Игоря В. Семенцова ([@igkuzm](https://github.com/igkuzm)). В процессе активного развития оригинальная кодовая база была полностью переписана с нуля из-за её морального и технического устаревания (отказ от самодельного `libtg` и устаревшего транспорта в пользу официального `tdlib`, полностью новый интерфейс UIKit, современная подсистема медиа и E2EE VoIP звонков под GPLv3).

## Отказ от ответственности

Программа предоставляется в образовательных целях и для сохранения старого оборудования. Используйте на свой страх и риск.
