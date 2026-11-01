# LegacyTG

Читать на других языках: [English](README.md)

Клиент Telegram для устройств на iOS 6.0–12.5.7. Два движка: `libtg` (лёгкий C MTProto) для 32-битных устройств, `tdlib` для всего современного.

## Поддерживаемые устройства

| Сборка | Размер | Целевые устройства |
|---|---|---|
| armv7 | ~8.8 МБ | iOS 6.0+ — iPhone 3GS/4/4S/5, iPad 2/3/4, iPod Touch 4/5 |
| arm64 | ~8.8 МБ | iOS 7.0–12.5.7 — iPhone 5s–X, iPad Air/Pro |
| Универсальная | ~16 МБ | Fat-бинарник, оба среза |

## Настройка

Перед сборкой настройте ключи API:

```bash
cp include/tg_config.h.example include/tg_config.h
```

Зарегистрируйтесь на https://my.telegram.org → API development tools, затем заполните `include/tg_config.h`:

```c
#define TG_API_ID   ВАШ_API_ID
#define TG_API_HASH "ВАШ_API_HASH"
```

`include/tg_config.h` добавлен в `.gitignore`.

## Структура репозитория

```
LegacyTG/
├── Makefile
├── src/
│   ├── App/         # вход приложения: main, AppDelegate, URL-роутинг
│   ├── Core/        # клиент, TDLib bridge, тема, стиль, логика устройства
│   ├── Controllers/ # ViewControllers
│   ├── Views/       # UIKit-компоненты, ячейки, иконки
│   ├── UI/          # переиспользуемые контролы (кнопки, поля, аватары)
│   ├── Media/       # декодеры (WebP-картинки, WebM-стикеры)
│   ├── Calls/       # VoIP и E2EE-звонки
│   └── Audio/       # голосовые сообщения
├── resources/       # Info.plist, шрифты, entitlements
├── images/          # иконки и ресурсы
├── third_party/     # libtgvoip, opus, ogg, …
├── tdlib/           # TDLib (git submodule)
├── libs/            # готовые библиотеки и WebP.framework
├── include/         # заголовки C, tg_config.h.example
├── compat/          # полифиллы (dyld TLV, шимы iOS 7)
├── tools/           # утилиты для хоста/устройства
├── scripts/         # скрипты сборки и деплоя
├── tests/           # юнит- и интеграционные тесты
└── build/           # результаты сборки (git-ignored)
```

## Сборка

Нужен Xcode с iOS SDK, затем:

```bash
brew install cmake gperf openssl@1.1 ccache
```

Клонируйте и соберите:

```bash
git clone --recursive https://github.com/bla1r1/iTgLegacy.git
cd iTgLegacy
make
```

### Цели Makefile

| Цель | Что делает |
|---|---|
| `make ipa` | Все три пакета (armv7, arm64, универсальный) |
| `make ipa-armv7` | 32-битный IPA для iOS 6.0+ |
| `make ipa-arm64` | 64-битный IPA для iOS 7.0–12.5.7 |
| `make app` | Только `.app`-бандл |
| `make deps` | Распаковать статические библиотеки в `build/libs` |
| `make tdlib` | Скомпилировать TDLib для iOS |
| `make clean` | Удалить `build/` |

## Автор и лицензия

- **[bla1r1](https://github.com/bla1r1)** — автор и мейнтейнер
- **GPLv3** — см. [LICENSE](LICENSE)

Проект начинался с прототипа [@igkuzm](https://github.com/igkuzm) и был полностью переписан с нуля — новый движок (TDLib вместо `libtg`), новый UIKit, медиапайплайн, E2EE-звонки.

> Программа предназначена для сохранения старого оборудования и в образовательных целях. Используйте на свой страх и риск.
