# Android release signing

GitHub Release에 올리는 Android artifact는 debug key가 아니라 release keystore로 서명해야 한다.
이 workflow는 `v*` tag 빌드에서만 signed APK와 AAB를 만든다.

## GitHub Actions secrets

Repository settings의 Actions secrets에 다음 값을 등록한다.

- `ANDROID_KEYSTORE_BASE64`: `upload-keystore.jks` 파일을 base64로 인코딩한 값
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: key alias
- `ANDROID_KEY_PASSWORD`: key password

PowerShell에서 keystore를 base64로 변환하는 예:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

## Keystore 생성 예

```powershell
keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`upload-keystore.jks`와 `key.properties`는 절대 commit하지 않는다. 둘 다 Android `.gitignore`에 포함되어 있다.

## Play Protect

APK를 직접 sideload하면 서명되어 있어도 기기 정책이나 Play Protect 설정에 따라 경고가 남을 수 있다.
배포용으로는 workflow가 생성하는 `app-release.aab`를 Play Console internal testing 또는 closed testing에 올리는 방식이 가장 안정적이다.
