-- ملف SQL لنقل قاعدة البيانات إلى Neon
-- قم بتشغيل هذا الملف في Neon SQL Editor بعد الاتصال

-- 1. إنشاء جميع الجداول
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    owner_user_id UUID,
    subscription_expires_at TIMESTAMPTZ,
    subscription_plan TEXT DEFAULT 'monthly',
    subscription_status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public_users (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'employee',
    can_delete_data BOOLEAN DEFAULT false,
    can_edit_data BOOLEAN DEFAULT false,
    can_create_users BOOLEAN DEFAULT false,
    created_by UUID REFERENCES public_users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS invoices_in (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    amount NUMERIC(15, 2) NOT NULL DEFAULT 0,
    currency TEXT DEFAULT 'TRY',
    description TEXT,
    date DATE DEFAULT CURRENT_DATE,
    category TEXT,
    status TEXT DEFAULT 'pending',
    created_by UUID REFERENCES public_users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS invoices_out (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    amount NUMERIC(15, 2) NOT NULL DEFAULT 0,
    currency TEXT DEFAULT 'TRY',
    description TEXT,
    date DATE DEFAULT CURRENT_DATE,
    category TEXT,
    status TEXT DEFAULT 'pending',
    created_by UUID REFERENCES public_users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS partners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public_users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. إنشاء الفهارس
CREATE INDEX IF NOT EXISTS idx_tenants_created_at ON tenants(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_public_users_tenant_id ON public_users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_public_users_email ON public_users(email);
CREATE INDEX IF NOT EXISTS idx_invoices_in_tenant_id ON invoices_in(tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoices_in_date ON invoices_in(date DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_out_tenant_id ON invoices_out(tenant_id);
CREATE INDEX IF NOT EXISTS idx_invoices_out_date ON invoices_out(date DESC);
CREATE INDEX IF NOT EXISTS idx_partners_tenant_id ON partners(tenant_id);
CREATE INDEX IF NOT EXISTS idx_partners_type ON partners(type);
CREATE INDEX IF NOT EXISTS idx_inventory_items_tenant_id ON inventory_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_employees_tenant_id ON employees(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_id ON audit_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at DESC);

-- 3. إنشاء Function لتحديث updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 4. إنشاء Triggers
DROP TRIGGER IF EXISTS update_tenants_updated_at ON tenants;
CREATE TRIGGER update_tenants_updated_at BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_public_users_updated_at ON public_users;
CREATE TRIGGER update_public_users_updated_at BEFORE UPDATE ON public_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 5. إضافة بيانات المشرف العام (admin@ibrahim.com)
-- ملاحظة: يجب إنشاء المستخدم في Supabase Auth أولاً، ثم استخدام ID الخاص به هنا
-- أو يمكنك إنشاء tenant بدون owner_user_id أولاً، ثم تحديثه لاحقاً

INSERT INTO public_users (
    id,
    name,
    email,
    role,
    can_delete_data,
    can_edit_data,
    can_create_users,
    created_at
) VALUES (
    gen_random_uuid(), -- سيتم تحديثه لاحقاً بـ ID الحقيقي من Supabase Auth
    'المشرف العام',
    'admin@ibrahim.com',
    'SUPER_ADMIN',
    true,
    true,
    true,
    NOW()
)
ON CONFLICT (email) DO UPDATE SET
    role = 'SUPER_ADMIN',
    can_delete_data = true,
    can_edit_data = true,
    can_create_users = true;

-- 6. إنشاء tenant تجريبي (اختياري)
-- يمكن حذف هذا إذا كنت تريد أن يبدأ المستخدمون بإنشاء متاجرهم الخاصة

-- رسالة نجاح
DO $$
BEGIN
    RAISE NOTICE 'تم إنشاء قاعدة البيانات في Neon بنجاح!';
    RAISE NOTICE 'الخطوة التالية: قم بإنشاء المستخدم في Supabase Auth ثم قم بتحديث ID في public_users';
END $$;

