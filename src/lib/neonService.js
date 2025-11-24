// خدمة Neon لاستبدال Supabase تماماً
import { getNeonClient } from './neonClient';

const sql = getNeonClient();

// Helper functions - استخدام Web Crypto API للتشفير
const hashPassword = async (password) => {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
};

const verifyPassword = async (password, hash) => {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const computedHash = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return computedHash === hash;
};

// Helper to perform a query with tenant filtering
const getByTenant = async (table, tenantId, { select = '*', orderBy = { column: 'created_at', ascending: false } } = {}) => {
  if (!tenantId) {
    console.warn(`getByTenant: No tenantId provided for table ${table}`);
    return [];
  }
  
  try {
    let query = `SELECT ${select} FROM ${table} WHERE tenant_id = $1`;
    if (orderBy && orderBy.column) {
      query += ` ORDER BY ${orderBy.column} ${orderBy.ascending ? 'ASC' : 'DESC'}`;
    }
    const result = await sql.unsafe(query, [tenantId]);
    return result || [];
  } catch (error) {
    console.error(`getByTenant error for ${table}:`, error);
    return [];
  }
};

// Helper to insert a record with tenant ID
const createRecord = async (table, data, tenantId) => {
  if (!tenantId) throw new Error('Tenant ID is required');
  
  const payload = { ...data, tenant_id: tenantId };
  const columns = Object.keys(payload);
  const values = Object.values(payload);
  const placeholders = values.map((_, i) => `$${i + 1}`).join(', ');
  
  const query = `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${placeholders}) RETURNING *`;
  const result = await sql.unsafe(query, values);
  return result[0];
};

// Helper to update a record ensuring it belongs to the tenant
const updateRecord = async (table, id, data, tenantId) => {
  if (!tenantId) throw new Error('Tenant ID is required');

  const columns = Object.keys(data);
  const setClause = columns.map((col, i) => `${col} = $${i + 2}`).join(', ');
  const values = [id, ...Object.values(data)];
  
  const query = `UPDATE ${table} SET ${setClause} WHERE id = $1 AND tenant_id = $${values.length + 1} RETURNING *`;
  values.push(tenantId);
  
  const result = await sql.unsafe(query, values);
  if (!result || result.length === 0) throw new Error('Record not found or access denied');
  return result[0];
};

// Helper to delete a record ensuring it belongs to the tenant
const deleteRecord = async (table, id, tenantId) => {
  if (!tenantId) throw new Error('Tenant ID is required');

  const query = `DELETE FROM ${table} WHERE id = $1 AND tenant_id = $2`;
  await sql.unsafe(query, [id, tenantId]);
  return true;
};

const auditLog = async (tenantId, userId, action, details) => {
  try {
    await sql`
      INSERT INTO audit_logs (tenant_id, user_id, action, details)
      VALUES (${tenantId}, ${userId}, ${action}, ${JSON.stringify(details)})
    `;
  } catch (e) {
    console.error('Audit log failed', e);
  }
};

// --- Exported Service ---

export const neonService = {
  // Password utilities (exported for use in other components)
  hashPassword,
  verifyPassword,

  // Auth & User
  getUserByEmail: async (email) => {
    try {
      const result = await sql`SELECT * FROM users WHERE email = ${email} AND is_active = true LIMIT 1`;
      return result[0] || null;
    } catch (error) {
      console.error('getUserByEmail error:', error);
      return null;
    }
  },

  getUserProfile: async (userId) => {
    if (!userId) {
      console.warn('getUserProfile: No userId provided');
      return null;
    }
    
    try {
      const userResult = await sql`SELECT * FROM users WHERE id = ${userId} LIMIT 1`;
      const user = userResult[0];
      
      if (!user) return null;

      let tenant = null;
      if (user.tenant_id) {
        const tenantResult = await sql`SELECT * FROM tenants WHERE id = ${user.tenant_id} LIMIT 1`;
        tenant = tenantResult[0] || null;
      }

      return { ...user, tenant };
    } catch (error) {
      console.error('getUserProfile error:', error);
      return null;
    }
  },

  createUser: async (userData) => {
    try {
      const passwordHash = await hashPassword(userData.password);
      const result = await sql`
        INSERT INTO users (email, password_hash, name, tenant_id, role, can_delete_data, can_edit_data, can_create_users, created_by)
        VALUES (${userData.email}, ${passwordHash}, ${userData.name}, ${userData.tenant_id || null}, ${userData.role || 'employee'}, 
                ${userData.can_delete_data || false}, ${userData.can_edit_data || false}, ${userData.can_create_users || false}, ${userData.created_by || null})
        RETURNING *
      `;
      return result[0];
    } catch (error) {
      console.error('createUser error:', error);
      throw error;
    }
  },

  verifyPassword: async (email, password) => {
    try {
      const user = await neonService.getUserByEmail(email);
      if (!user) return null;
      
      const isValid = await verifyPassword(password, user.password_hash);
      if (!isValid) return null;
      
      // تحديث last_login
      await sql`UPDATE users SET last_login = NOW() WHERE id = ${user.id}`;
      
      return user;
    } catch (error) {
      console.error('verifyPassword error:', error);
      return null;
    }
  },

  createTenant: async (tenantName, ownerUserId) => {
    try {
      const result = await sql`
        INSERT INTO tenants (name, owner_user_id)
        VALUES (${tenantName}, ${ownerUserId})
        RETURNING *
      `;
      return result[0];
    } catch (error) {
      console.error('createTenant error:', error);
      throw error;
    }
  },
  
  createUserProfile: async (userProfile) => {
    try {
      const passwordHash = userProfile.password ? await hashPassword(userProfile.password) : null;
      const columns = Object.keys(userProfile).filter(k => k !== 'password');
      const values = Object.values(userProfile).filter((_, i) => Object.keys(userProfile)[i] !== 'password');
      
      if (passwordHash) {
        columns.push('password_hash');
        values.push(passwordHash);
      }
      
      const placeholders = values.map((_, i) => `$${i + 1}`).join(', ');
      const query = `INSERT INTO users (${columns.join(', ')}) VALUES (${placeholders}) RETURNING *`;
      const result = await sql.unsafe(query, values);
      return result[0];
    } catch (error) {
      console.error('createUserProfile error:', error);
      throw error;
    }
  },

  getUsers: (tenantId) => getByTenant('users', tenantId),
  updateUser: (id, data, tenantId) => updateRecord('users', id, data, tenantId),
  updateUserAdmin: async (id, data) => {
    // تحديث المستخدم بدون tenant_id (للمدير فقط)
    try {
      const columns = Object.keys(data);
      const setClause = columns.map((col, i) => `${col} = $${i + 2}`).join(', ');
      const values = [id, ...Object.values(data)];
      const query = `UPDATE users SET ${setClause} WHERE id = $1 RETURNING *`;
      const result = await sql.unsafe(query, values);
      if (!result || result.length === 0) throw new Error('User not found');
      return result[0];
    } catch (error) {
      console.error('updateUserAdmin error:', error);
      throw error;
    }
  },
  deleteUser: (id, tenantId) => deleteRecord('users', id, tenantId),

  // System Settings (Admin only)
  getSystemSettings: async () => {
    try {
      const result = await sql`SELECT * FROM system_settings ORDER BY key`;
      const settings = {};
      result.forEach(row => {
        settings[row.key] = row.value;
      });
      return settings;
    } catch (error) {
      console.error('getSystemSettings error:', error);
      return {};
    }
  },

  updateSystemSetting: async (key, value, userId) => {
    try {
      await sql`
        INSERT INTO system_settings (key, value, updated_by)
        VALUES (${key}, ${value}, ${userId})
        ON CONFLICT (key) DO UPDATE SET value = ${value}, updated_by = ${userId}, updated_at = NOW()
      `;
      return true;
    } catch (error) {
      console.error('updateSystemSetting error:', error);
      throw error;
    }
  },

  // Partners
  getPartners: (tenantId) => getByTenant('partners', tenantId),
  createPartner: (data, tenantId) => createRecord('partners', data, tenantId),
  updatePartner: (id, data, tenantId) => updateRecord('partners', id, data, tenantId),
  deletePartner: (id, tenantId) => deleteRecord('partners', id, tenantId),

  // Invoices
  getInvoicesIn: async (tenantId) => {
    if (!tenantId) return [];
    try {
      return await getByTenant('invoices_in', tenantId);
    } catch (error) {
      console.error('getInvoicesIn error:', error);
      return [];
    }
  },
  createInvoiceIn: (data, tenantId) => createRecord('invoices_in', data, tenantId),
  updateInvoiceIn: (id, data, tenantId) => updateRecord('invoices_in', id, data, tenantId),
  deleteInvoiceIn: (id, tenantId) => deleteRecord('invoices_in', id, tenantId),

  getInvoicesOut: async (tenantId) => {
    if (!tenantId) return [];
    try {
      return await getByTenant('invoices_out', tenantId);
    } catch (error) {
      console.error('getInvoicesOut error:', error);
      return [];
    }
  },
  createInvoiceOut: (data, tenantId) => createRecord('invoices_out', data, tenantId),
  updateInvoiceOut: (id, data, tenantId) => updateRecord('invoices_out', id, data, tenantId),
  deleteInvoiceOut: (id, tenantId) => deleteRecord('invoices_out', id, tenantId),

  // Inventory
  getInventory: async (tenantId) => {
    if (!tenantId) return [];
    try {
      return await getByTenant('inventory_items', tenantId);
    } catch (error) {
      console.error('getInventory error:', error);
      return [];
    }
  },
  createInventory: (data, tenantId) => createRecord('inventory_items', data, tenantId),
  updateInventory: (id, data, tenantId) => updateRecord('inventory_items', id, data, tenantId),
  deleteInventory: (id, tenantId) => deleteRecord('inventory_items', id, tenantId),

  // Employees
  getEmployees: async (tenantId) => {
    if (!tenantId) return [];
    try {
      return await getByTenant('employees', tenantId);
    } catch (error) {
      console.error('getEmployees error:', error);
      return [];
    }
  },
  createEmployee: (data, tenantId) => createRecord('employees', data, tenantId),
  updateEmployee: (id, data, tenantId) => updateRecord('employees', id, data, tenantId),
  deleteEmployee: (id, tenantId) => deleteRecord('employees', id, tenantId),

  // Payroll
  getPayroll: (tenantId) => getByTenant('payroll', tenantId),
  createPayroll: (data, tenantId) => createRecord('payroll', data, tenantId),
  deletePayroll: (id, tenantId) => deleteRecord('payroll', id, tenantId),

  // Tenants (Admin only)
  getAllTenants: async () => {
    try {
      const result = await sql`
        SELECT t.*, u.name as owner_name, u.email as owner_email
        FROM tenants t
        LEFT JOIN users u ON t.owner_user_id = u.id
        ORDER BY t.created_at DESC
      `;
      return result || [];
    } catch (error) {
      console.error('getAllTenants error:', error);
      return [];
    }
  },

  updateTenant: async (tenantId, data) => {
    try {
      const columns = Object.keys(data);
      const setClause = columns.map((col, i) => `${col} = $${i + 2}`).join(', ');
      const values = [tenantId, ...Object.values(data)];
      const query = `UPDATE tenants SET ${setClause} WHERE id = $1 RETURNING *`;
      const result = await sql.unsafe(query, values);
      return result[0];
    } catch (error) {
      console.error('updateTenant error:', error);
      throw error;
    }
  },

  // Logs
  getAuditLogs: (tenantId) => getByTenant('audit_logs', tenantId),
  log: auditLog,
};
