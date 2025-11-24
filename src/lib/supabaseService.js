
import { supabase } from '@/lib/customSupabaseClient';

/**
 * Helper to perform a query with tenant filtering.
 * @param {string} table - Table name
 * @param {string} tenantId - Tenant ID to filter by
 * @param {Object} [options] - select string, etc.
 */
const   getByTenant = async (table, tenantId, { select = '*', orderBy = { column: 'created_at', ascending: false } } = {}) => {
  if (!tenantId) {
    console.warn(`getByTenant: No tenantId provided for table ${table}`);
    return [];
  }
  
  try {
    let query = supabase
      .from(table)
      .select(select)
      .eq('tenant_id', tenantId);

    if (orderBy && orderBy.column) {
      query = query.order(orderBy.column, { ascending: orderBy.ascending });
    }

    const { data, error } = await query;
    if (error) {
      console.error(`getByTenant error for ${table}:`, error);
      return [];
    }
    return data || [];
  } catch (error) {
    console.error(`getByTenant exception for ${table}:`, error);
    return [];
  }
};

/**
 * Helper to insert a record with tenant ID.
 */
const createRecord = async (table, data, tenantId) => {
  if (!tenantId) throw new Error('Tenant ID is required');
  
  const payload = { ...data, tenant_id: tenantId };
  const { data: result, error } = await supabase
    .from(table)
    .insert(payload)
    .select()
    .single();

  if (error) throw error;
  return result;
};

/**
 * Helper to update a record ensuring it belongs to the tenant.
 */
const updateRecord = async (table, id, data, tenantId) => {
  if (!tenantId) throw new Error('Tenant ID is required');

  const { data: result, error } = await supabase
    .from(table)
    .update(data)
    .eq('id', id)
    .eq('tenant_id', tenantId) // Security: Ensure ownership
    .select()
    .single();

  if (error) throw error;
  return result;
};

/**
 * Helper to delete a record ensuring it belongs to the tenant.
 */
const deleteRecord = async (table, id, tenantId) => {
  if (!tenantId) throw new Error('Tenant ID is required');

  const { error } = await supabase
    .from(table)
    .delete()
    .eq('id', id)
    .eq('tenant_id', tenantId);

  if (error) throw error;
  return true;
};

const auditLog = async (tenantId, userId, action, details) => {
  try {
    await supabase.from('audit_logs').insert({
      tenant_id: tenantId,
      user_id: userId,
      action,
      details,
    });
  } catch (e) {
    console.error('Audit log failed', e);
  }
};

// --- Exported Service ---

export const supabaseService = {
  // Auth & User
  getUserProfile: async (userId) => {
    try {
      // First get user profile
      const { data: profile, error: profileError } = await supabase
        .from('public_users')
        .select('*')
        .eq('id', userId)
        .single();
      
      if (profileError || !profile) {
        console.warn('User profile not found:', profileError);
        return null;
      }

      // Then get tenant info if tenant_id exists
      let tenant = null;
      if (profile.tenant_id) {
        const { data: tenantData, error: tenantError } = await supabase
          .from('tenants')
          .select('*')
          .eq('id', profile.tenant_id)
          .single();
        
        if (!tenantError && tenantData) {
          tenant = tenantData;
        }
      }

      return { ...profile, tenant };
    } catch (error) {
      console.error('getUserProfile error:', error);
      return null;
    }
  },

  createTenant: async (tenantName, ownerUserId) => {
    // 1. Create Tenant
    const { data: tenant, error: tError } = await supabase
      .from('tenants')
      .insert({ name: tenantName, owner_user_id: ownerUserId })
      .select()
      .single();
    if (tError) throw tError;

    // 2. Create Public Profile linked to tenant
    // Note: The calling auth registration logic usually handles the auth.users creation.
    return tenant;
  },
  
  createUserProfile: async (userProfile) => {
      const { data, error } = await supabase.from('public_users').insert(userProfile).select().single();
      if(error) throw error;
      return data;
  },

  getUsers: (tenantId) => getByTenant('public_users', tenantId),
  // createUser: handled via auth flow, but this can serve for admin adding users (requires edge function ideally for auth.users)
  updateUser: (id, data, tenantId) => updateRecord('public_users', id, data, tenantId),
  deleteUser: (id, tenantId) => deleteRecord('public_users', id, tenantId),

  // Partners
  getPartners: (tenantId) => getByTenant('partners', tenantId),
  createPartner: (data, tenantId) => createRecord('partners', data, tenantId),
  updatePartner: (id, data, tenantId) => updateRecord('partners', id, data, tenantId),
  deletePartner: (id, tenantId) => deleteRecord('partners', id, tenantId),

  // Invoices
  getInvoicesIn: (tenantId) => getByTenant('invoices_in', tenantId, { select: '*, partners(name)' }),
  createInvoiceIn: (data, tenantId) => createRecord('invoices_in', data, tenantId),
  updateInvoiceIn: (id, data, tenantId) => updateRecord('invoices_in', id, data, tenantId),
  deleteInvoiceIn: (id, tenantId) => deleteRecord('invoices_in', id, tenantId),

  getInvoicesOut: (tenantId) => getByTenant('invoices_out', tenantId, { select: '*, partners(name)' }),
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

  // Logs
  getAuditLogs: (tenantId) => getByTenant('audit_logs', tenantId),
  log: auditLog,
};
