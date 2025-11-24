# دليل النشر على Netlify

## المتطلبات
- حساب على Netlify
- قاعدة بيانات Neon جاهزة
- متغيرات البيئة

## خطوات النشر

### 1. إعداد قاعدة البيانات Neon

قم بتشغيل ملف `setup_neon_complete.sql` في Neon SQL Editor.

### 2. إنشاء حساب المدير

قم بتشغيل السكربت التالي لإنشاء hash كلمة المرور:

```javascript
// في console المتصفح أو Node.js
const hashPassword = async (password) => {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
};

const hash = await hashPassword('Admin@123456');
console.log('Hash:', hash);
```

ثم قم بتحديث `password_hash` في جدول `users` للمستخدم `admin@ibrahim.com`.

### 3. إعداد متغيرات البيئة في Netlify

في Netlify Dashboard:
1. اذهب إلى Site settings > Environment variables
2. أضف المتغير التالي:
   - `VITE_NEON_DATABASE_URL`: رابط اتصال قاعدة البيانات من Neon

### 4. رفع المشروع إلى GitHub

```bash
git add .
git commit -m "Migrate to Neon, remove Supabase"
git push origin main
```

### 5. ربط Netlify مع GitHub

1. اذهب إلى Netlify Dashboard
2. اضغط على "Add new site" > "Import an existing project"
3. اختر GitHub واختر المستودع
4. إعدادات البناء:
   - Build command: `npm run build`
   - Publish directory: `dist`

### 6. التحقق من النشر

بعد النشر، تحقق من:
- تسجيل الدخول بحساب المدير: `admin@ibrahim.com` / `Admin@123456`
- التحقق من إعدادات المدير
- التحقق من فصل المتاجر

## ملاحظات مهمة

1. **الأمان**: تأكد من عدم كشف `VITE_NEON_DATABASE_URL` في الكود العام
2. **CORS**: تأكد من إعداد CORS في Neon للسماح لـ Netlify
3. **الصلاحيات**: تأكد من أن مدير المتجر يمكنه فقط إدارة موظفيه

## استكشاف الأخطاء

- إذا فشل البناء: تحقق من متغيرات البيئة
- إذا فشل الاتصال بقاعدة البيانات: تحقق من `VITE_NEON_DATABASE_URL`
- إذا فشل تسجيل الدخول: تحقق من hash كلمة المرور في قاعدة البيانات

