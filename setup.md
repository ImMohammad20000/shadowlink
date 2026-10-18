## موارد مورد نیاز

### کامپیوتر با 2 اینترنت:

کامپیوتر با سیستم عامل ویندوز که همزمان به 2 "اینترنت استارلینک" و "اینترنت ایران" دسترسی داره

مثال: "اینترنت استارلینک" رو بصورت کابل LAN و "اینترنت ایران" رو بصورت Wi-Fi به کامپیوتر متصل میکنیم:

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/nic.png)

### سرور ایران:

یک سرور ایران با سیستم عامل لینوکس (ترجیها Debian یا Ubuntu) که ازش به عنوان یک پل ارتباطی بین استارلینک و کاربر عمل میکنه

#### نکته:

در زمان خرید حتی ارزونترین سرور هم برای این پروژه جوابگو هستش و نیازی به خرید سرور گرون قیمت نیست!

## آموزش راه اندازی: سرور

ابتدا با استفاده از ssh به سرور متصل میشیم و فایل `shadowlink-server.zip` آخرین Release رو دانلود و استخراج میکنیم. این فایل باینری‌های لازم برای نصب آفلاین را دارد. کلون سورس به تنهایی کافی نیست.

```bash
unzip shadowlink-server.zip
```

نکته: اگه اینترنت سرور قطع بود یا به هر دلیلی نتونستید فایل پروژه رو دانلود کنید، باید بصورت دستی فایل پروژه رو تو سرور آپلود کنید.

حالا وارد فولدر server پروژه میشیم و اسکریپت رو اجرا میکنیم:

```bash
cd server && chmod +x shadowlink.sh && ./shadowlink.sh
```

#### نکته: برای اجرای دستورات بالا احتیاج به دسترسی root داریم:

```bash
sudo su
```

#### منو اصلی:

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/server_menu.png)

بعد از انتخاب گزینه اول یعنی "Setup" فقط در چند ثانیه سرور ما راه اندازی میشه:

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/server_setup.png)

#### 1: اصلاعات پنل مدیریت کاربر

رمز عبور پنل در هر نصب به صورت تصادفی تولید و در خروجی اسکریپت نمایش داده می‌شود؛ آن را ذخیره کنید. پنل 3x-ui v3+ روی پورت 7092 اجرا می‌شود.

#### 2: توکن UUID که باید به بخش Client تحویل داده بشه

### نکته خیلی مهم:

در صورت نیاز، یوزرنیم، پسورد، پورت و مسیر web را از تنظیمات پنل تغییر دهید.

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/panel_auth.png)

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/panel_url.png)

## آموزش راه اندازی: کلاینت

بعد از اتصال دو اینترنت "استارلینک" و "ایران"، پروژه رو روی کامپیوتر دانلود کرده، وارد فولدر client میشیم. در ویندوز فایل `shadowlink.bat` و در سیستم های Bash-based فایل `shadowlink.sh` رو اجرا میکنیم:

#### نکته:

در نسخه Bash، اسکریپت به صورت خودکار باینری Linux برنامه `xray` رو از دایرکتوری `client/linux/<arch>/xray` (مثلا `client/linux/amd64/xray` یا `client/linux/arm64/xray`) بر اساس معماری سیستم اجرا میکنه. در صورت نیاز میتونید با متغیر `XRAY_BIN` مسیر باینری دلخواهتون رو override کنید.

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/client_script.png)

بعد از اجرا شدن، برنامه لیست کارت شبکه های موجود در کامپیوتر رو نمایش میده و در مرحله اول از ما میخواد که کارت شبکه ای که برای "اینترنت استارلینک" هست رو انتخاب کنیم (در این مثال کارت شبکه "اینترنت استارلینک" من گزینه 1 هستش):

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/client_starlink_nic.png)

در مرحله دوم باید کارت شبکه ای که برای "اینترنت ایران" هستش رو از لیست انتخاب کنید (در این مثال کارت شبکه "اینترنت ایران" من گزینه 10 هستش):

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/client_iran_nic.png)

حالا آدرس IP سرور ایران رو وارد میکنیم:

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/client_bridge_ip.png)

و در آخر توکن UUID که تو اسکریپت اول نمایش داده شده بود رو وارد میکنیم:

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/client_uuid.png)

با وارد کردن موارد خواسته شده، تانل شما بین کامپیوتر و سرور برقرار میشه:

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/client_tunnel.png)

## آموزش راه اندازی: ساخت اکانت

با برقرار شدن تانل، کافیه وارد پنل مدیریت کاربری شده و اکانت با تنظیمات دلخواهتون بسازید:

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/panel_client1.png)

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/panel_client2.png)

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/panel_client3.png)

و تمام! حالا کافیه لینک یا QR Code اکانت ساخته شده رو برای شخصی که میخواید ارسال کنید:

![App Screenshot](https://raw.githubusercontent.com/ImMohammad20000/shadowlink/main/pics/panel_client4.png)

#### نکته: پیشنهاد میشه از پروتکل "shadowsocks" با رمزنگاری "CHACHA20_IETF_POLY1305" استفاده کنید تا بتونید از نرم افزار Outline برای اتصال راحت تر تو تمام پلتفرم ها استفاده کنید

برای ریست یا حذف پنل و تانل روی سرور ایران، کافیه مجددا فایل `shadowlink.sh` اجرا کرده و گزینه "Reset" یا "Uninstall" رو انتخاب کنید
