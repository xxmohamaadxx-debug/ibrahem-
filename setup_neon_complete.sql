-- ملف SQL كامل لإعداد Neon مع نظام مصادقة محلي
-- قم بتشغيل هذا الملف في Neon SQL Editor

-- 1. إنشاء Extension للـ UUID إذا لم يكن موجوداً
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. إنشاء جدول Settings للنظام (إعدادات الإدمن)
CREATE TABLE IF NOT EXISTS system_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key TEXT UNIQUE NOT NULL,
    value TEXT,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by UUID
);

-- 3. إنشاء جدول Users للمصادقة المحلية
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    name TEXT NOT NULL,
    tenant_id UUID,
    role TEXT DEFAULT 'employee',
    can_delete_data BOOLEAN DEFAULT false,
    can_edit_data BOOLEAN DEFAULT false,
    can_create_users BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    last_login TIMESTAMPTZ,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. إنشاء جدول Tenants
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    subscription_expires_at TIMESTAMPTZ,
    subscription_plan TEXT DEFAULT 'monthly',
    subscription_status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. تحديث foreign key في users بعد إنشاء tenants
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_tenant_id_fkey;
ALTER TABLE users ADD CONSTRAINT users_tenant_id_fkey 
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE SET NULL;

-- 6. إنشاء باقي الجداول
CREATE TABLE IF NOT EXISTS invoices_in (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    amount NUMERIC(15, 2) NOT NULL DEFAULT 0,
    currency TEXT DEFAULT 'TRY',
    description TEXT,
    date DATE DEFAULT CURRENT_DATE,
    category TEXT,
    status TEXT DEFAULT 'pending',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS invoices_out (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    amount NUMERIC(15, 2) NOT NULL DEFAULT 0,
    currency TEXT DEFAULT 'TRY',
    description TEXT,
    date DATE DEFAULT CURRENT_DATE,
    category TEXT,
    status TEXT DEFAULT 'pending',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS partners (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'Customer',
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    address TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS inventory_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    sku TEXT,
    name TEXT NOT NULL,
    unit TEXT DEFAULT 'piece',
    quantity NUMERIC(10, 2) DEFAULT 0,
    min_stock NUMERIC(10, 2) DEFAULT 5,
    price NUMERIC(15, 2) DEFAULT 0,
    currency TEXT DEFAULT 'TRY',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    position TEXT,
    base_salary NUMERIC(15, 2) DEFAULT 0,
    currency TEXT DEFAULT 'TRY',
    hire_date DATE,
    status TEXT DEFAULT 'Active',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payroll (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    employee_id UUID,
    employee_name TEXT NOT NULL,
    base_salary NUMERIC(15, 2) DEFAULT 0,
    currency TEXT DEFAULT 'TRY',
    month INTEGER,
    year INTEGER,
    deductions NUMERIC(15, 2) DEFAULT 0,
    bonuses NUMERIC(15, 2) DEFAULT 0,
    net_salary NUMERIC(15, 2) DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. إنشاء الفهارس
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_tenants_created_at ON tenants(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tenants_owner_user_id ON tenants(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_in_tenant_id ON invoices_in(tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoices_in_date ON invoices_in(date DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_out_tenant_id ON invoices_out(tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoices_out_date ON invoices_out(date DESC);
CREATE INDEX IF NOT EXISTS idx_partners_tenant_id ON partners(tenant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_items_tenant_id ON inventory_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_employees_tenant_id ON employees(tenant_id);
CREATE INDEX IF NOT EXISTS idx_payroll_tenant_id ON payroll(tenant_id);
CREATE INDEX IF NOT EXISTS idx_payroll_created_at ON payroll(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_id ON audit_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at DESC);

-- 8. إنشاء Function لتحديث updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 9. إنشاء Triggers
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_tenants_updated_at ON tenants;
CREATE TRIGGER update_tenants_updated_at BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_system_settings_updated_at ON system_settings;
CREATE TRIGGER update_system_settings_updated_at BEFORE UPDATE ON system_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 10. إنشاء حساب الإدمن الأساسي
-- كلمة المرور: Admin@123456
-- يتم تشفيرها باستخدام bcrypt (سيتم في الكود)
-- لكن هنا نضيف المستخدم بدون tenant (super admin)
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
    '$2b$10$rI8V5JxJhJxJhJxJhJxJhOuJxJhJxJhJxJhJxJhJxJhJxJhJxJhJu', -- سيتم تحديثها من الكود
    'المشرف العام',
    'SUPER_ADMIN',
    true,
    true,
    true,
    true,
    NOW()
)
ON CONFLICT (email) DO UPDATE SET
    role = 'SUPER_ADMIN',
    can_delete_data = true,
    can_edit_data = true,
    can_create_users = true,
    is_active = true;

-- 11. إضافة إعدادات النظام الافتراضية
INSERT INTO system_settings (key, value, description) VALUES
    ('support_phone', '+963994054027', 'رقم الجوال للدعم'),
    ('support_whatsapp', '+963994054027', 'رقم الواتساب للدعم'),
    ('support_email', 'systemibrahem@gmail.com', 'البريد الإلكتروني للدعم')
ON CONFLICT (key) DO NOTHING;

-- 12. Function للتحقق من كلمة المرور (اختياري - يمكن استخدامها في SQL)
-- لكن التشفير سيتم في Node.js/JavaScript

-- رسالة نجاح
DO $$
BEGIN
    RAISE NOTICE '✅ تم إنشاء قاعدة البيانات في Neon بنجاح!';
    RAISE NOTICE '📧 حساب الإدمن: admin@ibrahim.com';
    RAISE NOTICE '🔐 كلمة المرور: Admin@123456';
    RAISE NOTICE '⚠️  يرجى تشغيل سكربت إنشاء hash كلمة المرور من الكود';
END $$;

