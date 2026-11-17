# Systemless Hosts dla KernelSU / KernelSU-Next

**Autor:** deepseek-flash · **Licencja:** MIT · **Wersja:** v1.0.0

Moduł podmienia `/system/etc/hosts` na plik trzymany w `/data/adb/modules/ksu-hosts`.
Partycja system pozostaje nietknięta, a zmiany (np. zapis z AdAway) przeżywają restart.

> **EN (short):** Systemless `/system/etc/hosts` module for KernelSU / KernelSU-Next
> (and APatch). Bind-mounts a hosts file from the module directory onto
> `/system/etc/hosts` in `post-fs-data`, with an overlayfs fallback, so AdAway writes
> persist across reboots. No metamodule and no "OverlayFS" toggle required.
> Install the ZIP in the KernelSU manager, reboot. Ships with a ~76k-domain
> StevenBlack list.

Sprawdzone podejście: `mount --bind` pliku hosts. Jeśli bind jest zablokowany,
moduł robi fallback na `overlayfs` z `upperdir` w katalogu modułu.
Nie wymaga włączonego „OverlayFS” w ustawieniach KernelSU ani metamodułu
(`meta-overlayfs`) — montuje hosts samodzielnie (`skip_mount`).

## Co jest w środku

| Plik | Rola |
|---|---|
| `common.sh` | logika: wykrywanie montowania, bind/overlay, poprawianie praw i kontekstu SELinux |
| `post-fs-data.sh` | montuje hosts najwcześniej jak się da (przed startem apek) |
| `post-mount.sh` | ponawia po montowaniu modułów przez KSU (gdyby KSU nadpisał bind) |
| `service.sh` | trzecia próba w late_start service (np. tryb late-load) |
| `action.sh` | przycisk „Action” w menedżerze: status + ponowne podpięcie bez restartu |
| `update_hosts.sh` | pobiera listę blokującą i podmienia ją w locie (bez restartu) |
| `customize.sh` | instalator: zachowuje poprzednią listę, ustawia prawa, tworzy `skip_mount` |
| `system/etc/hosts` | domyślna lista (StevenBlack, ~76k domen) |

## Instalacja

1. Menedżer KernelSU → **Moduły → Zainstaluj z pliku** → wybierz
   `ksu-hosts-v1.0.0.zip`.
2. Restart urządzenia.

Alternatywnie przez adb:

```sh
adb push ksu-hosts-v1.0.0.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/ksu-hosts-v1.0.0.zip'
adb reboot
```

Po restarcie hosts już blokuje (jest w nim lista domyślna), więc AdAway nie jest
do niczego niezbędny.

## AdAway

- W AdAway wybierz **Root based ad blocker** (nie „VPN”).
- NIE włączaj w AdAway opcji systemless/module — AdAway tworzy wtedy własny
  moduł `hosts`, którego KernelSU-Next bez overlayfs nie zamontuje. Tutaj
  `/system/etc/hosts` jest już zapisywalny, więc AdAway pisze wprost do niego.
- Po „Aktualizuj hosty” nie trzeba restartu: zapis idzie przez bind mount
  do pliku w `/data/adb/modules/ksu-hosts/system/etc/hosts`.
- Kopia listy jest trzymana w `/data/adb/systemless-hosts/hosts`, więc
  reinstalacja modułu nie kasuje wygenerowanej listy.

## Własna lista bez AdAway

```sh
su -c 'sh /data/adb/modules/ksu-hosts/update_hosts.sh'
# albo z własnym źródłem (URL lub plik lokalny):
su -c 'sh /data/adb/modules/ksu-hosts/update_hosts.sh https://example.com/hosts.txt'
su -c 'sh /data/adb/modules/ksu-hosts/update_hosts.sh /sdcard/moja-lista.txt'
```

Lista jest normalizowana (tylko `0.0.0.0`/`127.0.0.1`, lowercase, dedupe,
komentarze obcinane) i zapisywana „w miejscu”, żeby bind mount dalej wskazywał
ten sam plik. Zmiana działa od razu.

## Weryfikacja

```sh
su -c 'grep -c "^0\.0\.0\.0 " /system/etc/hosts'      # liczba wpisów
su -c 'grep hosts /proc/mounts'                        # bind (albo overlay na /system/etc)
su -c 'ls -Z /system/etc/hosts'                        # kontekst: u:object_r:system_file:s0
su -c 'sh /data/adb/modules/ksu-hosts/action.sh'       # status + ponowne podpięcie
su -c 'cat /data/adb/systemless-hosts/apply.log'       # log montowania
su -c 'ping -c1 doubleclick.net'                       # powinno nie rozwiązać nazwy
```

## Rozwiązywanie problemów

- **Reklama w przeglądarce, ale `ping` blokuje** → w profilu aplikacji
  (KernelSU → Superuser → dana apka) wyłącz **„Unmount modules”**; inaczej KSU
  odmontowuje też nasz hosts w przestrzeni tej apki. Znany problem AdAway +
  ZygiskNext/Shamiko.
- **Zero blokowania w całym systemie** → sprawdź `apply.log`. Jeśli jest tam
  `ERROR: nie udalo sie podmienic hosts`, jądro nie pozwoliło ani na bind, ani
  na overlay (nietypowe). Wyślij log.
- **AdAway mówi „nie można zapisać”** → upewnij się, że moduł jest włączony
  i hosts jest podmontowany (`grep hosts /proc/mounts`), potem w AdAway
  wybierz ponownie tryb root.
- **Private DNS / DoH** omija hosts — dla pełnego blokowania wyłącz
  „Prywatny DNS” albo ustaw blokujący resolver.
- Po podmianie listy część apek trzyma własny cache DNS — wystarczy zamknąć
  i otworzyć apkę (albo restart).

## Odinstalowanie

Menedżer → Moduły → usuń `Systemless Hosts`. Po restarcie wraca oryginalny
`/system/etc/hosts` z partycji system. Kopia listy w
`/data/adb/systemless-hosts/` zostaje (do usunięcia ręcznie).

## Testy (dla ciekawych)

```sh
busybox ash tests/run-tests.sh   # 60 asercji, bez roota, z falszywym mountem
```
