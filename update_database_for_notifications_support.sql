-- تحديث قاعدة البيانات لإضافة نظام الإشعارات والدعم والصلاحيات المحسنة
-- قم بتشغيل هذا الملف في Neon SQL Editor

-- 1. إنشاء جدول الإشعارات
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- 'system', 'alert', 'support', 'subscription'
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_tenant ON notifications(tenant_id, created_at);

-- 2. إنشاء جدول تذاكر الدعم والمراسلة
CREATE TABLE IF NOT EXISTS support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    subject TEXT NOT NULL,
    message TEXT NOT NULL,
    status TEXT DEFAULT 'open', -- 'open', 'in_progress', 'resolved', 'closed'
    priority TEXT DEFAULT 'medium', -- 'low', 'medium', 'high', 'urgent'
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL, -- للمدير أو الأدمن
    is_from_admin BOOLEAN DEFAULT false, -- إذا كانت الرسالة من الأدمن
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- 3. إنشاء جدول رسائل الدعم (للردود والمحادثات)
CREATE TABLE IF NOT EXISTS support_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID REFERENCES support_tickets(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    message TEXT NOT NULL,
    attachments JSONB, -- لتخزين روابط الملفات المرفقة
    is_from_admin BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_tenant ON support_tickets(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_user ON support_tickets(user_id, status);
CREATE INDEX IF NOT EXISTS idx_support_messages_ticket ON support_messages(ticket_id, created_at);

-- 4. تحديث جدول users لإضافة حقول الصلاحيات المحسنة
ALTER TABLE users ADD COLUMN IF NOT EXISTS can_be_edited_by_store_owner BOOLEAN DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS notification_preferences JSONB DEFAULT '{"email": true, "push": true, "sound": true}'::jsonb;

-- 5. إنشاء جدول لتتبع قراءة الإشعارات
CREATE TABLE IF NOT EXISTS notification_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID REFERENCES notifications(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(notification_id, user_id)
);

-- 6. إنشاء دالة لتحديث updated_at تلقائياً
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 7. إنشاء trigger لتحديث updated_at في support_tickets
DROP TRIGGER IF EXISTS update_support_tickets_updated_at ON support_tickets;
CREATE TRIGGER update_support_tickets_updated_at
    BEFORE UPDATE ON support_tickets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 8. إنشاء دالة لإرسال إشعار عند إنشاء تذكرة دعم جديدة
CREATE OR REPLACE FUNCTION notify_new_support_ticket()
RETURNS TRIGGER AS $$
BEGIN
    -- إرسال إشعار للأدمن عن التذكرة الجديدة
    INSERT INTO notifications (tenant_id, user_id, type, title, message)
    SELECT 
        NULL, -- للأدمن، لا tenant_id
        u.id,
        'support',
        'تذكرة دعم جديدة',
        'تم إنشاء تذكرة دعم جديدة: ' || NEW.subject
    FROM users u
    WHERE u.role = 'Super Admin' OR u.email = 'admin@ibrahim.com'
    LIMIT 10; -- إرسال لأول 10 أدمن
    
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 9. إنشاء trigger لإرسال الإشعارات عند إنشاء تذكرة دعم
DROP TRIGGER IF EXISTS trigger_notify_new_support_ticket ON support_tickets;
CREATE TRIGGER trigger_notify_new_support_ticket
    AFTER INSERT ON support_tickets
    FOR EACH ROW
    WHEN (NEW.is_from_admin = false)
    EXECUTE FUNCTION notify_new_support_ticket();

-- 10. إنشاء دالة لإرسال إشعار عند إضافة رسالة جديدة في التذكرة
CREATE OR REPLACE FUNCTION notify_new_support_message()
RETURNS TRIGGER AS $$
DECLARE
    ticket_owner_id UUID;
    ticket_tenant_id UUID;
BEGIN
    -- الحصول على معلومات التذكرة
    SELECT user_id, tenant_id INTO ticket_owner_id, ticket_tenant_id
    FROM support_tickets
    WHERE id = NEW.ticket_id;
    
    -- إرسال إشعار للمستخدم أو الأدمن حسب من أرسل الرسالة
    IF NEW.is_from_admin THEN
        -- إذا كانت الرسالة من الأدمن، أرسل إشعار لمستخدم التذكرة
        IF ticket_owner_id IS NOT NULL THEN
            INSERT INTO notifications (tenant_id, user_id, type, title, message)
            VALUES (
                ticket_tenant_id,
                ticket_owner_id,
                'support',
                'رد جديد على تذكرة الدعم',
                'تم إضافة رد جديد على تذكرتك: ' || substring(NEW.message from 1 for 50)
            );
        END IF;
    ELSE
        -- إذا كانت الرسالة من المستخدم، أرسل إشعار للأدمن
        INSERT INTO notifications (tenant_id, user_id, type, title, message)
        SELECT 
            ticket_tenant_id,
            u.id,
            'support',
            'رد جديد على تذكرة الدعم',
            'تم إضافة رد جديد على التذكرة: ' || substring(NEW.message from 1 for 50)
        FROM users u
        WHERE (u.role = 'Super Admin' OR u.email = 'admin@ibrahim.com')
        LIMIT 10;
    END IF;
    
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 11. إنشاء trigger لإرسال الإشعارات عند إضافة رسالة
DROP TRIGGER IF EXISTS trigger_notify_new_support_message ON support_messages;
CREATE TRIGGER trigger_notify_new_support_message
    AFTER INSERT ON support_messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_support_message();

-- 12. إنشاء View لتسهيل استعلام الإشعارات غير المقروءة
CREATE OR REPLACE VIEW unread_notifications_count AS
SELECT 
    user_id,
    COUNT(*) as unread_count
FROM notifications
WHERE is_read = false
GROUP BY user_id;

-- 13. تحديث permissions - السماح لمدير المتجر بتعديل بيانات المحاسبين
-- (هذا يتم تطبيقه في الكود، لكن يمكن إضافة constraint للتأكيد)
COMMENT ON COLUMN users.can_be_edited_by_store_owner IS 'إذا كان true، يمكن لمدير المتجر تعديل بيانات هذا المستخدم حتى لو كان له صلاحيات';

-- 14. إضافة indexes لتحسين الأداء
CREATE INDEX IF NOT EXISTS idx_support_tickets_status_priority ON support_tickets(status, priority);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned_to ON support_tickets(assigned_to) WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type, created_at);

-- تم الانتهاء من التحديثات
SELECT 'Database updated successfully for notifications and support system!' as status;

