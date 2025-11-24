// سكربت Node.js لإنشاء hash كلمة المرور للمدير
import { getNeonClient } from '../src/lib/neonClient.js';
import crypto from 'crypto';

const sql = getNeonClient();

const hashPassword = (password) => {
  return crypto.createHash('sha256').update(password).digest('hex');
};

const createAdmin = async () => {
  try {
    const password = 'Admin@123456';
    const passwordHash = hashPassword(password);
    
    console.log('🔐 Hash كلمة المرور:', passwordHash);
    
    // إنشاء أو تحديث حساب المدير
    const result = await sql`
      INSERT INTO users (
        email,
        password_hash,
        name,
        role,
        can_delete_data,
        can_edit_data,
        can_create_users,
        is_active
      ) VALUES (
        'admin@ibrahim.com',
        ${passwordHash},
        'المشرف العام',
        'SUPER_ADMIN',
        true,
        true,
        true,
        true
      )
      ON CONFLICT (email) DO UPDATE SET
        password_hash = EXCLUDED.password_hash,
        role = 'SUPER_ADMIN',
        can_delete_data = true,
        can_edit_data = true,
        can_create_users = true,
        is_active = true
      RETURNING *
    `;
    
    console.log('✅ تم إنشاء/تحديث حساب المدير بنجاح!');
    console.log('📧 البريد:', result[0].email);
    console.log('👤 الاسم:', result[0].name);
    
    await sql.end();
    process.exit(0);
  } catch (error) {
    console.error('❌ خطأ في إنشاء حساب المدير:', error);
    await sql.end();
    process.exit(1);
  }
};

createAdmin();

