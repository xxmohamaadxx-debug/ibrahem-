-- سكربت لإنشاء حساب المدير مع hash كلمة المرور
-- كلمة المرور: Admin@123456
-- Hash باستخدام SHA-256: سيتم إنشاؤه من JavaScript

-- أولاً، احذف المستخدم القديم إن وجد
DELETE FROM users WHERE email = 'admin@ibrahim.com';

-- إنشاء حساب المدير الجديد
-- ملاحظة: يجب تشغيل هذا السكربت بعد إنشاء hash كلمة المرور من JavaScript
-- يمكنك استخدام: await neonService.hashPassword('Admin@123456')

INSERT INTO users (
    id,
    email,
    password_hash,
    name,
    role,
    can_delete_data,
    can_edit_data,
    can_create_users,
    is_active,
    created_at
) VALUES (
    uuid_generate_v4(),
    'admin@ibrahim.com',
    'PLACEHOLDER_HASH', -- استبدل هذا بـ hash كلمة المرور من JavaScript
    'المشرف العام',
    'SUPER_ADMIN',
    true,
    true,
    true,
    true,
    NOW()
)
ON CONFLICT (email) DO UPDATE SET
    password_hash = EXCLUDED.password_hash,
    role = 'SUPER_ADMIN',
    can_delete_data = true,
    can_edit_data = true,
    can_create_users = true,
    is_active = true;

-- رسالة نجاح
DO $$
BEGIN
    RAISE NOTICE '✅ تم إنشاء/تحديث حساب المدير بنجاح!';
    RAISE NOTICE '📧 البريد: admin@ibrahim.com';
    RAISE NOTICE '🔐 كلمة المرور: Admin@123456';
    RAISE NOTICE '⚠️  تأكد من تحديث password_hash في قاعدة البيانات';
END $$;

