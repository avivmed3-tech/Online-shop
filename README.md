# Online-shop

קטלוג הזמנות **B2B** — כל לקוח עסקי מתחבר ורואה את המחירים האישיים שלו (לפי אחוז הנחה), מבצע הזמנות שנשמרות, ובעל העסק מנהל מוצרים, לקוחות והזמנות.

**קישור לאתר:** https://avivmed3-tech.github.io/Online-shop/

## ארכיטקטורה

- **Frontend:** `catalog.html` — אפליקציית React (קובץ יחיד, PWA) שמתארחת ב-GitHub Pages.
- **Backend:** Supabase (Postgres + Auth + Edge Functions), פרויקט `online-shop-b2b`.

### תפקידים
- **admin** (בעל העסק): מנהל מוצרים, פותח חשבונות לקוחות + קובע אחוז הנחה, וצופה בכל ההזמנות.
- **customer** (לקוח עסקי): רואה קטלוג עם המחיר האישי שלו, מזמין, וצופה בהיסטוריית ההזמנות שלו.

### אבטחה
- **RLS** על כל הטבלאות — לקוח רואה רק את הנתונים שלו; אדמין רואה הכל.
- **תמחור בצד השרת** — מחיר היחידה בהזמנה מחושב ב-trigger מ-`base_price` × (1 − הנחה), כך שלא ניתן לזייף מחיר מהדפדפן.
- יצירת חשבונות לקוח נעשית דרך Edge Function (`create-customer`) המאמתת שהקורא הוא אדמין ומשתמשת ב-service-role בצד השרת בלבד.

## מבנה
```
catalog.html                         # האפליקציה (React + Supabase JS)
supabase/migrations/0001_b2b_schema.sql   # סכמה + RLS + טריגרים
supabase/functions/create-customer/       # פתיחת לקוח (admin בלבד)
```

## הגדרה
ב-`catalog.html`, בתוך `CONFIG`: `supabaseUrl`, `supabaseAnonKey`, ו-`whatsappNumber` (מספר העסק לקבלת הזמנות).
