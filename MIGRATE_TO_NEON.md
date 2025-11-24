# دليل نقل قاعدة البيانات إلى Neon

## الخطوات المطلوبة

### 1. إعداد Neon Database

قم بتشغيل الأوامر التالية في terminal:

```bash
# تهيئة Neon CLI
npx neonctl@latest init

# الاتصال بقاعدة البيانات
psql 'postgresql://neondb_owner:npg_TYtfnOlr2oW7@ep-holy-frog-ahulw0nk-pooler.c-3.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require'
```

### 2. تشغيل ملف SQL في Neon

بعد الاتصال بقاعدة البيانات، قم بتشغيل ملف `migrate_to_neon.sql`:

```sql
-- في Neon SQL Editor أو عبر psql
\i migrate_to_neon.sql
```

### 3. إنشاء مستخدم Admin في Supabase Auth

1. اذهب إلى Supabase Dashboard
2. افتح Authentication > Users
3. قم بإنشاء مستخدم جديد:
   - Email: `admin@ibrahim.com`
   - Password: (اختر كلمة مرور قوية)
   - User ID: (انسخ هذا ID)

### 4. تحديث بيانات Admin في Neon

بعد الحصول على User ID من Supabase، قم بتشغيل:

```sql
-- استبدل USER_ID_HERE بـ ID الحقيقي من Supabase
UPDATE public_users 
SET id = 'USER_ID_HERE'::uuid
WHERE email = 'admin@ibrahim.com';
```

### 5. تحديث الاتصال في الكود

قم بتحديث `src/lib/customSupabaseClient.js` لاستخدام Neon:

```javascript
// ملاحظة: Supabase Auth سيستخدم Supabase
// لكن البيانات ستأتي من Neon
```

### 6. إعداد Supabase للمراجعة

يمكنك استخدام Supabase للمصادقة (Auth) فقط، والبيانات من Neon.

أو يمكنك نقل كل شيء إلى Neon والاستغناء عن Supabase تماماً.

## بيانات Admin الافتراضية

- **Email**: `admin@ibrahim.com`
- **Password**: (يجب إنشاؤها في Supabase Auth)
- **Role**: `SUPER_ADMIN`
- **Permissions**: جميع الصلاحيات مفعلة

## ملاحظات مهمة

1. **المصادقة (Auth)**: يجب أن تبقى في Supabase لأن Supabase يدير Auth بشكل احترافي
2. **البيانات**: يمكن نقلها بالكامل إلى Neon
3. **الاتصال المختلط**: يمكن استخدام Supabase Auth + Neon Database

## البديل: استخدام Neon بالكامل

إذا أردت نقل كل شيء إلى Neon:
1. استخدم Supabase Auth فقط للمصادقة
2. جميع البيانات الأخرى من Neon
3. استخدم Supabase PostgREST للوصول للبيانات من Neon

