
import React, { createContext, useContext, useState, useEffect } from 'react';
import { supabase } from '@/lib/customSupabaseClient';
import { supabaseService } from '@/lib/supabaseService';
import { toast } from '@/components/ui/use-toast';
import { ROLES } from '@/lib/constants';

const AuthContext = createContext(null);

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
};

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [tenant, setTenant] = useState(null);
  const [loading, setLoading] = useState(true);
  const [initialized, setInitialized] = useState(false);

  const fetchProfile = async (sessionUser) => {
    try {
      if (!sessionUser) {
        setUser(null);
        setTenant(null);
        return;
      }

      // Get User Profile (includes tenant info now)
      const profileResult = await supabaseService.getUserProfile(sessionUser.id).catch(() => null);
      
      if (!profileResult) {
        // If no profile, check if admin user
        const adminEmails = ['systemibrahem@gmail.com', 'admin@ibrahim.com'];
        if (adminEmails.includes(sessionUser.email?.toLowerCase())) {
          setUser({ ...sessionUser, role: ROLES.SUPER_ADMIN, isSuperAdmin: true });
          setLoading(false);
          setInitialized(true);
          return;
        }
        setUser(null);
        setTenant(null);
        setLoading(false);
        setInitialized(true);
        return;
      }

      const profile = profileResult;
      const tenantInfo = profile.tenant || null;

      if (profile) {
        // Check if user is super admin - support multiple admin emails
        const adminEmails = ['systemibrahem@gmail.com', 'admin@ibrahim.com'];
        const isSuperAdmin = adminEmails.includes(profile.email?.toLowerCase()) || profile.role === ROLES.SUPER_ADMIN;
        
        const userData = {
          ...sessionUser,
          ...profile,
          id: sessionUser.id, // Ensure ID consistency
          isSuperAdmin: isSuperAdmin,
          isStoreOwner: profile.role === ROLES.STORE_OWNER,
        };

        // Check Subscription Expiry
        if (tenantInfo && !userData.isSuperAdmin) {
           const expiresAt = new Date(tenantInfo.subscription_expires_at);
           const now = new Date();
           const diffDays = Math.ceil((expiresAt - now) / (1000 * 60 * 60 * 24));
           
           tenantInfo.daysRemaining = diffDays;
           tenantInfo.isExpired = diffDays <= 0;

          if (tenantInfo.isExpired) {
            toast({
              title: "انتهت صلاحية الاشتراك",
              description: "انتهت صلاحية اشتراك متجرك. يرجى التواصل مع المدير للتجديد.",
              variant: "destructive",
              duration: 10000
            });
          } else if (diffDays <= 7) {
            toast({
              title: "قرب انتهاء الاشتراك",
              description: `سينتهي اشتراكك خلال ${diffDays} يوم. يرجى التجديد قريباً.`,
              variant: "warning"
            });
          }
        }

        setUser(userData);
        setTenant(tenantInfo);
      } else {
        // Fallback for super admin initial seed scenario if profile missing
        const adminEmails = ['systemibrahem@gmail.com', 'admin@ibrahim.com'];
        if (adminEmails.includes(sessionUser.email?.toLowerCase())) {
           setUser({ ...sessionUser, role: ROLES.SUPER_ADMIN, isSuperAdmin: true });
        } else {
           setUser(sessionUser);
        }
      }
    } catch (error) {
      console.error("Auth setup error:", error);
      setUser(sessionUser);
    } finally {
      setLoading(false);
      setInitialized(true);
    }
  };

  useEffect(() => {
    let mounted = true;

    const initAuth = async () => {
      try {
        const { data: { session }, error } = await supabase.auth.getSession();
        if (mounted) await fetchProfile(session?.user);
      } catch (error) {
        console.error("Auth initialization error:", error);
        if (mounted) {
          setUser(null);
          setLoading(false);
          setInitialized(true);
        }
      }
    };

    initAuth();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (_event, session) => {
        if (mounted) await fetchProfile(session?.user);
      }
    );

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, []);

  const login = async (email, password) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  };

  const register = async ({ name, storeName, email, password }) => {
    try {
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email,
        password,
        options: { data: { name } }
      });

      if (authError) throw authError;
      if (!authData.user) throw new Error('Registration failed');

      // Creating tenant
      const tenant = await supabaseService.createTenant(storeName, authData.user.id);
      
      // Create owner profile
      await supabaseService.createUserProfile({
          id: authData.user.id,
          tenant_id: tenant.id,
          name,
          email,
          role: ROLES.STORE_OWNER,
          can_delete_data: true,
          can_edit_data: true,
          can_create_users: true,
          created_by: authData.user.id
      });

      toast({ title: 'Account Created!', description: 'Welcome to Ibrahim Accounting System.' });
      return authData;
    } catch (error) {
      toast({ title: 'Registration Failed', description: error.message, variant: 'destructive' });
      throw error;
    }
  };

  const logout = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setTenant(null);
    window.location.href = '/login';
  };

  // Permission Helpers
  const canDelete = user?.isSuperAdmin || (user?.isStoreOwner && !tenant?.isExpired) || user?.can_delete_data;
  const canEdit = user?.isSuperAdmin || (user?.isStoreOwner && !tenant?.isExpired) || user?.can_edit_data;
  const canCreateUsers = user?.isSuperAdmin || (user?.isStoreOwner && !tenant?.isExpired) || user?.can_create_users;
  const isExpired = tenant?.isExpired && !user?.isSuperAdmin;

  if (loading && !initialized) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-orange-500"></div>
      </div>
    );
  }

  return (
    <AuthContext.Provider value={{ 
      user, 
      tenant, 
      login, 
      register, 
      logout, 
      loading,
      permissions: { canDelete, canEdit, canCreateUsers, isExpired }
    }}>
      {children}
    </AuthContext.Provider>
  );
};
