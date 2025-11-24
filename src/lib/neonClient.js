// عميل Neon للاتصال بقاعدة البيانات مباشرة
import postgres from 'postgres';

const NEON_DATABASE_URL = import.meta.env.VITE_NEON_DATABASE_URL || 
  'postgresql://neondb_owner:npg_TYtfnOlr2oW7@ep-holy-frog-ahulw0nk-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require';

// إنشاء عميل PostgreSQL
let sql = null;

export const getNeonClient = () => {
  if (!sql) {
    sql = postgres(NEON_DATABASE_URL, {
      max: 10,
      idle_timeout: 20,
      connect_timeout: 10,
    });
  }
  return sql;
};

export default getNeonClient();

