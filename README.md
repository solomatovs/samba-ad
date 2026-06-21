# Добавить krb5.conf на клиентской машине (где будет запущен браузер)

```bash
sudo tee /etc/krb5.conf >/dev/null <<'EOF'
[libdefaults]
    default_realm = EXAMPLE.COM
    dns_lookup_kdc = false
    dns_lookup_realm = false
    forwardable = true

[realms]
    EXAMPLE.COM = {
        kdc = dc1.example.com
        admin_server = dc1.example.com
    }

[domain_realm]
    .example.com = EXAMPLE.COM
    example.com = EXAMPLE.COM
EOF
```

# Проверить что доступны порты AD, Kerberos

```bash
nmap -Pn dc1.example.com -p 389,636,88,464,3268,3269
```

```
PORT     STATE SERVICE
88/tcp   open  kerberos-sec
389/tcp  open  ldap
464/tcp  open  kpasswd5
636/tcp  open  ldapssl
3268/tcp open  globalcatLDAP
3269/tcp open  globalcatLDAPssl
```

# Запросить тикет пользователя

```bash
kdestroy -A                      # удаляем существующие тикеты
kinit solomatovs@EXAMPLE.COM     # запросит пароль
klist                            # должен появиться krbtgt/EXAMPLE.COM
```

# Автополучение тикета при входе (macOS, LaunchAgent)

## Пароль в Keychain

```bash
security add-generic-password -a solomatovs -s krb-login -w 'ПАРОЛЬ'
```

## Скрипт получения тикета

```bash
mkdir -p ~/bin
tee ~/bin/krb-login.sh >/dev/null <<'EOF'
#!/bin/bash
pw="$(security find-generic-password -s krb-login -w 2>/dev/null)" || exit 0
printf '%s' "$pw" | kinit --password-file=STDIN solomatovs@EXAMPLE.COM
EOF
chmod +x ~/bin/krb-login.sh
```

## LaunchAgent (запуск при входе + обновление раз в час)

```bash
tee ~/Library/LaunchAgents/com.example.kinit.plist >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.example.kinit</string>
  <key>ProgramArguments</key>
  <array><string>/Users/solomatovs/bin/krb-login.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>3600</integer>
</dict></plist>
EOF
```

## Установка / переустановка агента

```bash
# выгрузить старый, если уже стоит (идемпотентно, не падает если его нет)
launchctl bootout gui/$(id -u)/com.example.kinit 2>/dev/null || true
# загрузить агент
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.kinit.plist
# запустить сразу, не дожидаясь следующего входа
launchctl kickstart -k gui/$(id -u)/com.example.kinit
# проверить, что тикет получен
klist
```

## Обновить пароль (после смены пароля AD)

```bash
security delete-generic-password -s krb-login 2>/dev/null
security add-generic-password -a solomatovs -s krb-login -w 'НОВЫЙ_ПАРОЛЬ'
launchctl kickstart -k gui/$(id -u)/com.example.kinit
klist
```

## Отладка (если тикет не появился)

```bash
# выполнить скрипт вручную и увидеть ошибку kinit
~/bin/krb-login.sh; echo "exit=$?"
# логи агента: добавь в plist пути и перезапусти агент
#   <key>StandardOutPath</key><string>/tmp/krb-login.out</string>
#   <key>StandardErrorPath</key><string>/tmp/krb-login.err</string>
cat /tmp/krb-login.err
```

## Удалить агент

```bash
launchctl bootout gui/$(id -u)/com.example.kinit 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.example.kinit.plist
```

# Изменить политики браузера на возможность делегирования

## macOS

```bash
BUNDLE=$(defaults read /Applications/Yandex.app/Contents/Info CFBundleIdentifier)
defaults write "$BUNDLE" AuthServerAllowlist            -string "*example.com"
defaults write "$BUNDLE" AuthNegotiateDelegateAllowlist -string "*example.com"
```

## Windows

```
HKLM\SOFTWARE\Policies\YandexBrowser
  AuthServerAllowlist            (REG_SZ) = *example.com
  AuthNegotiateDelegateAllowlist (REG_SZ) = *example.com
```

## Linux

```bash
sudo mkdir -p /etc/yandex-browser/policies/managed
sudo tee /etc/yandex-browser/policies/managed/kerberos.json >/dev/null <<'EOF'
{
  "AuthServerAllowlist": "*example.com",
  "AuthNegotiateDelegateAllowlist": "*example.com"
}
EOF
```

# Переключение режима делегирования для учётки

## Проверить текущее состояние

```bash
docker exec samba-ad samba-tool delegation show boba-svc
```

## Сброс всех режимов

```bash
docker exec samba-ad samba-tool delegation for-any-service  boba-svc off
docker exec samba-ad samba-tool delegation for-any-protocol boba-svc off
```

## Режим 1: unconstrained

```bash
docker exec samba-ad samba-tool delegation for-any-service  boba-svc on
```

## Режим 2: constrained (S4U2Proxy)

```bash
docker exec samba-ad samba-tool delegation del-service      boba-svc postgres/postgres-17.example.com
docker exec samba-ad samba-tool delegation for-any-service  boba-svc off
docker exec samba-ad samba-tool delegation for-any-protocol boba-svc off
docker exec samba-ad samba-tool delegation add-service      boba-svc postgres/postgres-17.example.com
```

## Режим 3: constrained + protocol transition

```bash
docker exec samba-ad samba-tool delegation del-service      boba-svc postgres/postgres-17.example.com
docker exec samba-ad samba-tool delegation for-any-service  boba-svc off
docker exec samba-ad samba-tool delegation for-any-protocol boba-svc off
docker exec samba-ad samba-tool delegation for-any-protocol boba-svc on
docker exec samba-ad samba-tool delegation add-service      boba-svc postgres/postgres-17.example.com
```
