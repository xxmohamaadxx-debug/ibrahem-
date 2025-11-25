-- سكربت SQL كامل لإنشاء/تحديث حساب المدير
-- كلمة المرور: Admin@123456
-- Hash (SHA-256): ad89b64d66caa8e30e5d5ce4a9763f4ecc205814c412175f3e2c50027471426d

-- أولاً، احذف المستخدم القديم إن وجد (اختياري)
-- DELETE FROM users WHERE email = 'admin@ibrahim.com';

-- إنشاء أو تحديث حساب المدير
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
    COALESCE((SELECT id FROM users WHERE email = 'admin@ibrahim.com'), uuid_generate_v4()),
    'admin@ibrahim.com',
    'ad89b64d66caa8e30e5d5ce4a9763f4ecc205814c412175f3e2c50027471426d', -- Hash كلمة المرور: Admin@123456
    'المشرف العام',
    'SUPER_ADMIN',
    true,
    true,
    true,
    true,
    COALESCE((SELECT created_at FROM users WHERE email = 'admin@ibrahim.com'), NOW())
)
ON CONFLICT (email) DO UPDATE SET
    password_hash = EXCLUDED.password_hash,
    role = 'SUPER_ADMIN',
    can_delete_data = true,
    can_edit_data = true,
    can_create_users = true,
    is_active = true,
    updated_at = NOW();

-- التحقق من إنشاء المستخدم
SELECT 
    id,
    email,
    name,
    role,
    can_delete_data,
    can_edit_data,
    can_create_users,
    is_active,
    created_at
FROM users 
WHERE email = 'admin@ibrahim.com';

-- رسالة نجاح
DO $$
BEGIN
    RAISE NOTICE '✅ تم إنشاء/تحديث حساب المدير بنجاح!';
    RAISE NOTICE '📧 البريد: admin@ibrahim.com';
    RAISE NOTICE '🔐 كلمة المرور: Admin@123456';
    RAISE NOTICE '👤 الدور: SUPER_ADMIN';
END $$;

