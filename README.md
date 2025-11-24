# نظام إبراهيم للمحاسبة

نظام محاسبة متعدد المتاجر مبني على React و Neon PostgreSQL.

## المميزات

- ✅ نظام مصادقة محلي باستخدام Neon
- ✅ فصل كامل بين المتاجر (Multi-tenant)
- ✅ إدارة صلاحيات متقدمة
- ✅ واجهة عربية 100%
- ✅ إدارة الاشتراكات
- ✅ لوحة تحكم للمدير

## المتطلبات

- Node.js 18+
- قاعدة بيانات Neon
- متغيرات البيئة

## التثبيت

```bash
npm install
```

## إعداد قاعدة البيانات

1. قم بإنشاء قاعدة بيانات في Neon
2. قم بتشغيل `setup_neon_complete.sql` في Neon SQL Editor
3. قم بإنشاء hash كلمة المرور للمدير:

```javascript
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

4. قم بتحديث `password_hash` في جدول `users` للمستخدم `admin@ibrahim.com`

## متغيرات البيئة

أنشئ ملف `.env`:

```
VITE_NEON_DATABASE_URL=postgresql://user:password@host/database?sslmode=require
```

## التشغيل

```bash
npm run dev
```

## البناء للنشر

```bash
npm run build
```

## حساب المدير الافتراضي

- البريد: `admin@ibrahim.com`
- كلمة المرور: `Admin@123456`

## النشر على Netlify

راجع ملف `DEPLOY_NETLIFY.md` للتعليمات الكاملة.

## الرخصة

خاص

