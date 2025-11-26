-- ============================================
-- نظام إدارة متكامل لدعم أنواع متعددة من المتاجر والصالات
-- ============================================
-- تاريخ الإنشاء: 2024
-- الوصف: نظام شامل يدعم صالات الإنترنت، متاجر الإكسسوارات، المستودعات، ومتاجر المحروقات
-- ============================================

-- تفعيل الامتدادات المطلوبة
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================
-- القسم 1: أنواع المتاجر (Store Types) - يمكن للأدمن إدارتها
-- ============================================

CREATE TABLE IF NOT EXISTS store_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL, -- 'cyber_cafe', 'mobile_accessories', 'warehouse', 'fuel_station'
    name_ar TEXT NOT NULL,
    name_en TEXT,
    name_tr TEXT,
    description_ar TEXT,
    description_en TEXT,
    features JSONB, -- ميزات خاصة لكل نوع متجر
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    icon TEXT, -- أيقونة المتجر
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- إدراج أنواع المتاجر الافتراضية
INSERT INTO store_types (code, name_ar, name_en, name_tr, description_ar, features, sort_order) VALUES
('cyber_cafe', 'صالة إنترنت', 'Cyber Café', 'İnternet Cafe', 'صالة إنترنت تدعم الاشتراكات واستخدام الإنترنت', 
 '{"internet_subscriptions": true, "hourly_rates": true, "user_management": true, "speed_control": true}'::jsonb, 1),
('mobile_accessories', 'متجر إكسسوارات جوال', 'Mobile Accessories Store', 'Mobil Aksesuar Mağazası', 
 'متجر إكسسوارات مع خدمة الإنترنت', 
 '{"internet_subscriptions": true, "inventory_management": true, "sales": true, "warehouse": true}'::jsonb, 2),
('warehouse', 'مستودع', 'Warehouse', 'Depo', 'مستودع مرتبط بالمتجر', 
 '{"inventory_management": true, "stock_tracking": true, "reports": true}'::jsonb, 3),
('fuel_station', 'متجر محروقات', 'Fuel Station', 'Benzin İstasyonu', 
 'متجر محروقات - بيع وشراء وقود ومنتجات مرتبطة', 
 '{"fuel_management": true, "inventory_management": true, "sales": true, "purchases": true, "price_management": true}'::jsonb, 4)
ON CONFLICT (code) DO UPDATE SET 
    name_ar = EXCLUDED.name_ar,
    updated_at = NOW();

-- ============================================
-- القسم 2: تحديث جدول المتاجر لدعم أنواع المتاجر
-- ============================================

ALTER TABLE tenants 
ADD COLUMN IF NOT EXISTS store_type_id UUID REFERENCES store_types(id),
ADD COLUMN IF NOT EXISTS store_config JSONB DEFAULT '{}'::jsonb, -- إعدادات خاصة لكل متجر
ADD COLUMN IF NOT EXISTS address TEXT,
ADD COLUMN IF NOT EXISTS phone TEXT,
ADD COLUMN IF NOT EXISTS email TEXT,
ADD COLUMN IF NOT EXISTS tax_number TEXT;

CREATE INDEX IF NOT EXISTS idx_tenants_store_type ON tenants(store_type_id);

-- ============================================
-- القسم 3: المشتركين (Subscribers) - لصالات الإنترنت والمتاجر
-- ============================================

CREATE TABLE IF NOT EXISTS subscribers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    national_id TEXT, -- الرقم الوطني
    address TEXT,
    subscription_type TEXT NOT NULL CHECK (subscription_type IN ('daily', 'weekly', 'monthly', 'custom')),
    internet_speed TEXT, -- السرعة (مثال: "10Mbps", "100Mbps")
    internet_speed_kbps INTEGER, -- السرعة بالكيلوبايت
    start_date DATE NOT NULL,
    end_date DATE,
    is_active BOOLEAN DEFAULT true,
    is_suspended BOOLEAN DEFAULT false,
    suspended_reason TEXT,
    balance NUMERIC(15, 2) DEFAULT 0, -- الرصيد
    total_paid NUMERIC(15, 2) DEFAULT 0,
    total_used NUMERIC(15, 2) DEFAULT 0,
    currency TEXT DEFAULT 'TRY',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_by UUID REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_subscribers_tenant ON subscribers(tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_subscribers_dates ON subscribers(tenant_id, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_subscribers_active ON subscribers(tenant_id, is_active, is_suspended);

-- ============================================
-- القسم 4: الاشتراكات (Subscriptions)
-- ============================================

CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    subscriber_id UUID REFERENCES subscribers(id) ON DELETE CASCADE NOT NULL,
    subscription_type TEXT NOT NULL CHECK (subscription_type IN ('daily', 'weekly', 'monthly', 'custom')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    price NUMERIC(15, 2) NOT NULL,
    currency TEXT DEFAULT 'TRY',
    payment_method TEXT DEFAULT 'cash' CHECK (payment_method IN ('cash', 'transfer', 'credit')),
    payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'partial', 'overdue')),
    paid_amount NUMERIC(15, 2) DEFAULT 0,
    remaining_amount NUMERIC(15, 2),
    is_active BOOLEAN DEFAULT true,
    auto_renew BOOLEAN DEFAULT false,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_tenant ON subscriptions(tenant_id, end_date);
CREATE INDEX IF NOT EXISTS idx_subscriptions_subscriber ON subscriptions(subscriber_id, is_active);
CREATE INDEX IF NOT EXISTS idx_subscriptions_dates ON subscriptions(tenant_id, start_date, end_date);

-- ============================================
-- القسم 5: استخدام الإنترنت (Internet Usage)
-- ============================================

CREATE TABLE IF NOT EXISTS internet_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    subscriber_id UUID REFERENCES subscribers(id) ON DELETE CASCADE,
    session_start TIMESTAMPTZ NOT NULL,
    session_end TIMESTAMPTZ,
    duration_minutes INTEGER, -- مدة الاستخدام بالدقائق
    internet_speed TEXT,
    data_used_mb NUMERIC(15, 2), -- البيانات المستخدمة بالميغابايت
    cost NUMERIC(15, 2),
    currency TEXT DEFAULT 'TRY',
    payment_method TEXT DEFAULT 'cash' CHECK (payment_method IN ('cash', 'transfer', 'credit')),
    is_paid BOOLEAN DEFAULT false,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_internet_usage_tenant ON internet_usage(tenant_id, session_start DESC);
CREATE INDEX IF NOT EXISTS idx_internet_usage_subscriber ON internet_usage(subscriber_id, session_start DESC);
CREATE INDEX IF NOT EXISTS idx_internet_usage_date ON internet_usage(tenant_id, DATE(session_start));

-- ============================================
-- القسم 6: معاملات المشتركين (Subscriber Transactions)
-- ============================================

CREATE TABLE IF NOT EXISTS subscriber_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    subscriber_id UUID REFERENCES subscribers(id) ON DELETE CASCADE NOT NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('payment', 'recharge', 'usage', 'refund', 'suspension', 'activation')),
    amount NUMERIC(15, 2) NOT NULL,
    currency TEXT DEFAULT 'TRY',
    payment_method TEXT DEFAULT 'cash' CHECK (payment_method IN ('cash', 'transfer', 'credit')),
    description TEXT,
    reference_type TEXT, -- 'subscription', 'internet_usage', 'manual'
    reference_id UUID,
    balance_before NUMERIC(15, 2),
    balance_after NUMERIC(15, 2),
    transaction_date TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_subscriber_transactions_tenant ON subscriber_transactions(tenant_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_subscriber_transactions_subscriber ON subscriber_transactions(subscriber_id, transaction_date DESC);

-- ============================================
-- القسم 7: متجر المحروقات (Fuel Station Management)
-- ============================================

-- أنواع المحروقات
CREATE TABLE IF NOT EXISTS fuel_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    code TEXT NOT NULL, -- 'gasoline_95', 'gasoline_98', 'diesel', 'gas', etc.
    name_ar TEXT NOT NULL,
    name_en TEXT,
    name_tr TEXT,
    unit TEXT DEFAULT 'liter', -- 'liter', 'gallon', 'kg'
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tenant_id, code)
);

-- جدول معاملات المحروقات (بيع/شراء)
CREATE TABLE IF NOT EXISTS fuel_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    fuel_type_id UUID REFERENCES fuel_types(id) ON DELETE RESTRICT NOT NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('purchase', 'sale', 'adjustment', 'loss')),
    quantity NUMERIC(15, 3) NOT NULL, -- الكمية
    unit_price NUMERIC(15, 2) NOT NULL,
    total_amount NUMERIC(15, 2) NOT NULL,
    currency TEXT DEFAULT 'TRY',
    payment_method TEXT DEFAULT 'cash' CHECK (payment_method IN ('cash', 'transfer', 'credit')),
    reference_number TEXT, -- رقم المرجع (فاتورة، إيصال)
    supplier_customer_name TEXT, -- اسم المورد أو العميل
    transaction_date TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_by UUID REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_fuel_transactions_tenant ON fuel_transactions(tenant_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_fuel_transactions_type ON fuel_transactions(fuel_type_id, transaction_type);

-- جدول مخزون المحروقات
CREATE TABLE IF NOT EXISTS fuel_inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    fuel_type_id UUID REFERENCES fuel_types(id) ON DELETE RESTRICT NOT NULL,
    quantity NUMERIC(15, 3) NOT NULL DEFAULT 0,
    unit TEXT DEFAULT 'liter',
    min_stock_level NUMERIC(15, 3) DEFAULT 0, -- الحد الأدنى للمخزون
    max_stock_level NUMERIC(15, 3),
    last_purchase_date TIMESTAMPTZ,
    last_sale_date TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tenant_id, fuel_type_id)
);

CREATE INDEX IF NOT EXISTS idx_fuel_inventory_tenant ON fuel_inventory(tenant_id);

-- جدول أسعار المحروقات (للمتابعة التاريخية)
CREATE TABLE IF NOT EXISTS fuel_prices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    fuel_type_id UUID REFERENCES fuel_types(id) ON DELETE RESTRICT NOT NULL,
    price NUMERIC(15, 2) NOT NULL,
    currency TEXT DEFAULT 'TRY',
    price_type TEXT DEFAULT 'sale' CHECK (price_type IN ('sale', 'purchase')),
    effective_date DATE NOT NULL,
    end_date DATE,
    is_active BOOLEAN DEFAULT true,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_fuel_prices_tenant ON fuel_prices(tenant_id, fuel_type_id, effective_date DESC);

-- ============================================
-- القسم 8: إشعارات انتهاء الاشتراك (Subscription Notifications)
-- ============================================

CREATE TABLE IF NOT EXISTS subscription_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
    subscriber_id UUID REFERENCES subscribers(id) ON DELETE CASCADE NOT NULL,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE CASCADE,
    notification_type TEXT NOT NULL CHECK (notification_type IN ('expiring_soon', 'expired', 'renewal_reminder', 'payment_due')),
    days_before_expiry INTEGER, -- كم يوم قبل الانتهاء
    message_ar TEXT,
    message_en TEXT,
    message_tr TEXT,
    is_sent BOOLEAN DEFAULT false,
    sent_at TIMESTAMPTZ,
    notification_method TEXT CHECK (notification_method IN ('email', 'sms', 'in_app', 'all')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscription_notifications_tenant ON subscription_notifications(tenant_id, is_sent, created_at);
CREATE INDEX IF NOT EXISTS idx_subscription_notifications_subscriber ON subscription_notifications(subscriber_id, is_sent);

-- ============================================
-- القسم 9: Views للإحصائيات والتقارير
-- ============================================

-- View لمشتركين على وشك الانتهاء
CREATE OR REPLACE VIEW expiring_subscriptions AS
SELECT 
    s.tenant_id,
    s.id as subscriber_id,
    s.name as subscriber_name,
    s.phone,
    sub.id as subscription_id,
    sub.end_date,
    sub.remaining_amount,
    (sub.end_date - CURRENT_DATE) as days_remaining,
    CASE 
        WHEN (sub.end_date - CURRENT_DATE) < 0 THEN 'expired'
        WHEN (sub.end_date - CURRENT_DATE) <= 7 THEN 'expiring_soon'
        ELSE 'active'
    END as status
FROM subscribers s
JOIN subscriptions sub ON s.id = sub.subscriber_id
WHERE sub.is_active = true
ORDER BY sub.end_date ASC;

-- View لتقارير استخدام الإنترنت اليومية
CREATE OR REPLACE VIEW daily_internet_usage_summary AS
SELECT 
    tenant_id,
    DATE(session_start) as usage_date,
    COUNT(*) as total_sessions,
    SUM(duration_minutes) as total_minutes,
    SUM(data_used_mb) as total_data_mb,
    SUM(cost) as total_cost,
    currency,
    COUNT(DISTINCT subscriber_id) as unique_users
FROM internet_usage
GROUP BY tenant_id, DATE(session_start), currency;

-- View لتقارير محروقات يومية
CREATE OR REPLACE VIEW daily_fuel_summary AS
SELECT 
    ft.tenant_id,
    ft.fuel_type_id,
    ft.name_ar as fuel_name,
    DATE(ft.transaction_date) as transaction_date,
    SUM(CASE WHEN ft.transaction_type = 'purchase' THEN ft.quantity ELSE 0 END) as purchased_quantity,
    SUM(CASE WHEN ft.transaction_type = 'sale' THEN ft.quantity ELSE 0 END) as sold_quantity,
    SUM(CASE WHEN ft.transaction_type = 'purchase' THEN ft.total_amount ELSE 0 END) as purchase_amount,
    SUM(CASE WHEN ft.transaction_type = 'sale' THEN ft.total_amount ELSE 0 END) as sale_amount,
    ft.currency
FROM fuel_transactions ft
JOIN fuel_types ftp ON ft.fuel_type_id = ftp.id
GROUP BY ft.tenant_id, ft.fuel_type_id, ftp.name_ar, DATE(ft.transaction_date), ft.currency;

-- View لمخزون المحروقات الحالي
CREATE OR REPLACE VIEW current_fuel_inventory AS
SELECT 
    fi.tenant_id,
    fi.fuel_type_id,
    ft.name_ar as fuel_name,
    fi.quantity,
    fi.unit,
    fi.min_stock_level,
    fi.max_stock_level,
    CASE 
        WHEN fi.quantity <= fi.min_stock_level THEN 'low_stock'
        WHEN fi.max_stock_level IS NOT NULL AND fi.quantity >= fi.max_stock_level THEN 'high_stock'
        ELSE 'normal'
    END as stock_status,
    fi.last_purchase_date,
    fi.last_sale_date
FROM fuel_inventory fi
JOIN fuel_types ft ON fi.fuel_type_id = ft.id;

-- ============================================
-- القسم 10: Functions و Triggers
-- ============================================

-- Function لتحديث رصيد المشترك تلقائياً
CREATE OR REPLACE FUNCTION update_subscriber_balance()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.transaction_type IN ('payment', 'recharge') THEN
        UPDATE subscribers
        SET balance = balance + NEW.amount,
            total_paid = total_paid + NEW.amount,
            updated_at = NOW()
        WHERE id = NEW.subscriber_id;
    ELSIF NEW.transaction_type = 'usage' THEN
        UPDATE subscribers
        SET balance = balance - NEW.amount,
            total_used = total_used + NEW.amount,
            updated_at = NOW()
        WHERE id = NEW.subscriber_id;
    END IF;
    
    -- تحديث الرصيد قبل وبعد
    NEW.balance_before := (SELECT balance FROM subscribers WHERE id = NEW.subscriber_id);
    IF NEW.transaction_type IN ('payment', 'recharge') THEN
        NEW.balance_after := NEW.balance_before + NEW.amount;
    ELSIF NEW.transaction_type = 'usage' THEN
        NEW.balance_after := NEW.balance_before - NEW.amount;
    ELSE
        NEW.balance_after := NEW.balance_before;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_subscriber_balance
BEFORE INSERT ON subscriber_transactions
FOR EACH ROW
EXECUTE FUNCTION update_subscriber_balance();

-- Function لتحديث مخزون المحروقات تلقائياً
CREATE OR REPLACE FUNCTION update_fuel_inventory()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.transaction_type = 'purchase' THEN
        INSERT INTO fuel_inventory (tenant_id, fuel_type_id, quantity, last_purchase_date)
        VALUES (NEW.tenant_id, NEW.fuel_type_id, NEW.quantity, NEW.transaction_date)
        ON CONFLICT (tenant_id, fuel_type_id) DO UPDATE
        SET quantity = fuel_inventory.quantity + NEW.quantity,
            last_purchase_date = NEW.transaction_date,
            updated_at = NOW();
    ELSIF NEW.transaction_type = 'sale' THEN
        UPDATE fuel_inventory
        SET quantity = quantity - NEW.quantity,
            last_sale_date = NEW.transaction_date,
            updated_at = NOW()
        WHERE tenant_id = NEW.tenant_id AND fuel_type_id = NEW.fuel_type_id;
    ELSIF NEW.transaction_type = 'adjustment' THEN
        -- تعديل يدوي للمخزون
        INSERT INTO fuel_inventory (tenant_id, fuel_type_id, quantity)
        VALUES (NEW.tenant_id, NEW.fuel_type_id, NEW.quantity)
        ON CONFLICT (tenant_id, fuel_type_id) DO UPDATE
        SET quantity = NEW.quantity,
            updated_at = NOW();
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_fuel_inventory
AFTER INSERT ON fuel_transactions
FOR EACH ROW
EXECUTE FUNCTION update_fuel_inventory();

-- Function لإرسال إشعارات انتهاء الاشتراك
CREATE OR REPLACE FUNCTION create_expiry_notifications()
RETURNS void AS $$
BEGIN
    -- إنشاء إشعارات للمشتركين على وشك الانتهاء (7 أيام)
    INSERT INTO subscription_notifications (tenant_id, subscriber_id, subscription_id, notification_type, days_before_expiry, message_ar, is_sent)
    SELECT 
        s.tenant_id,
        s.id,
        sub.id,
        'expiring_soon',
        7,
        'تنبيه: اشتراكك سينتهي خلال ' || (sub.end_date - CURRENT_DATE) || ' يوم. يرجى التجديد.',
        false
    FROM subscribers s
    JOIN subscriptions sub ON s.id = sub.subscriber_id
    WHERE sub.is_active = true
    AND sub.end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
    AND NOT EXISTS (
        SELECT 1 FROM subscription_notifications sn
        WHERE sn.subscriber_id = s.id 
        AND sn.subscription_id = sub.id
        AND sn.notification_type = 'expiring_soon'
        AND sn.days_before_expiry = 7
    );
END;
$$ LANGUAGE plpgsql;

-- Function لتحديث updated_at تلقائياً
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- تطبيق triggers على الجداول الجديدة
CREATE TRIGGER update_store_types_updated_at
BEFORE UPDATE ON store_types
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscribers_updated_at
BEFORE UPDATE ON subscribers
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at
BEFORE UPDATE ON subscriptions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_fuel_transactions_updated_at
BEFORE UPDATE ON fuel_transactions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_fuel_inventory_updated_at
BEFORE UPDATE ON fuel_inventory
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- القسم 11: Indexes للأداء
-- ============================================

CREATE INDEX IF NOT EXISTS idx_store_types_active ON store_types(is_active, sort_order);
CREATE INDEX IF NOT EXISTS idx_subscribers_search ON subscribers(tenant_id, name, phone) USING gin(to_tsvector('arabic', name || ' ' || COALESCE(phone, '')));
CREATE INDEX IF NOT EXISTS idx_fuel_transactions_search ON fuel_transactions(tenant_id, transaction_type, transaction_date DESC);

-- ============================================
-- القسم 12: Permissions و Comments
-- ============================================

COMMENT ON TABLE store_types IS 'أنواع المتاجر - يمكن للأدمن إدارتها';
COMMENT ON TABLE subscribers IS 'المشتركين في صالات الإنترنت';
COMMENT ON TABLE subscriptions IS 'الاشتراكات - يومي، أسبوعي، شهري';
COMMENT ON TABLE internet_usage IS 'سجل استخدام الإنترنت';
COMMENT ON TABLE fuel_transactions IS 'معاملات المحروقات - بيع وشراء';
COMMENT ON TABLE fuel_inventory IS 'مخزون المحروقات الحالي';
COMMENT ON TABLE subscription_notifications IS 'إشعارات انتهاء الاشتراك';

-- ============================================
-- انتهاء التحديث
-- ============================================

SELECT 'تم إنشاء نظام إدارة متكامل لدعم أنواع متعددة من المتاجر والصالات بنجاح!' as status;

