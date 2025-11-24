
import React, { useState, useEffect } from 'react';
import { Helmet } from 'react-helmet';
import { useAuth } from '@/contexts/AuthContext';
import { useLanguage } from '@/contexts/LanguageContext';
import { supabase } from '@/lib/customSupabaseClient';
import { Button } from '@/components/ui/button';
import { Loader2, Plus, Store, Calendar, AlertTriangle, Phone, MessageCircle } from 'lucide-react';
import { toast } from '@/components/ui/use-toast';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { SUBSCRIPTION_PLANS, CONTACT_INFO } from '@/lib/constants';

const AdminPanel = () => {
  const { user } = useAuth();
  const { t } = useLanguage();
  const [stores, setStores] = useState([]);
  const [loading, setLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  
  // New Store Form
  const [formData, setFormData] = useState({
    storeName: '',
    ownerName: '',
    email: '',
    password: '',
    plan: 'monthly'
  });

  useEffect(() => {
    if (user?.isSuperAdmin) fetchStores();
  }, [user]);

  const fetchStores = async () => {
    try {
      // First get all tenants
      const { data: tenantsData, error: tenantsError } = await supabase
        .from('tenants')
        .select('*')
        .order('created_at', { ascending: false });
        
      if (tenantsError) throw tenantsError;
      
      // Then get owner info for each tenant
      const storesWithOwners = await Promise.all(
        (tenantsData || []).map(async (tenant) => {
          if (tenant.owner_user_id) {
            try {
              const { data: ownerData } = await supabase
                .from('public_users')
                .select('name, email')
                .eq('id', tenant.owner_user_id)
                .single();
              
              return { ...tenant, owner: ownerData || null };
            } catch (err) {
              console.warn('Owner fetch error for tenant:', tenant.id, err);
              return { ...tenant, owner: null };
            }
          }
          return { ...tenant, owner: null };
        })
      );
      
      setStores(storesWithOwners);
    } catch (error) {
      console.error("Fetch stores error:", error);
      toast({ 
        title: t('adminPanel.errors.loadFailed'), 
        description: error.message || t('adminPanel.errors.loadError'),
        variant: "destructive" 
      });
      setStores([]);
    } finally {
      setLoading(false);
    }
  };

  const handleCreateStore = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      // 1. Create Auth User (This requires service_role usually, but for demo we use regular signup 
      // and assume admin has permission or we simulate it via function if Supabase configured)
      // NOTE: In client-side Supabase, admin cannot create other users without logging out.
      // Ideally, this should call a Supabase Edge Function.
      // For this implementation, we will simulate by instructing to use the registration page
      // or showing a message.
      
      toast({ 
        title: t('adminPanel.errors.systemLimitation'), 
        description: t('adminPanel.errors.createStoreNote'),
        variant: "warning"
      });
      
      // Normally: 
      // await supabase.functions.invoke('admin-create-store', { body: formData })
      
      setDialogOpen(false);
    } catch (error) {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    } finally {
      setLoading(false);
    }
  };

  const handleExtendSubscription = async (storeId, currentExpiry, planId) => {
    const plan = Object.values(SUBSCRIPTION_PLANS).find(p => p.id === planId);
    const current = new Date(currentExpiry || Date.now());
    const newExpiry = new Date(current.setDate(current.getDate() + plan.durationDays));
    
    try {
      const { error } = await supabase
        .from('tenants')
        .update({ 
          subscription_expires_at: newExpiry.toISOString(),
          subscription_plan: planId,
          subscription_status: 'active'
        })
        .eq('id', storeId);

      if (error) throw error;
      toast({ title: t('adminPanel.success.subscriptionExtended') });
      fetchStores();
    } catch (error) {
      toast({ title: t('adminPanel.errors.updateFailed'), variant: "destructive" });
    }
  };

  if (!user?.isSuperAdmin) {
    return <div className="p-8 text-center text-red-500">{t('adminPanel.errors.accessDenied')}</div>;
  }

  return (
    <div className="space-y-6">
      <Helmet><title>{t('adminPanel.title')} - {t('common.systemName')}</title></Helmet>
      
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
            <h1 className="text-2xl md:text-3xl font-bold text-gray-900 dark:text-white">{t('adminPanel.title')}</h1>
            <p className="text-gray-500 dark:text-gray-400 mt-1">{t('adminPanel.subtitle')}</p>
        </div>
        <Button onClick={() => setDialogOpen(true)} className="bg-purple-600 hover:bg-purple-700 text-white">
          <Plus className="ml-2 rtl:mr-2 rtl:ml-0 h-4 w-4" /> {t('adminPanel.createNewStore')}
        </Button>
      </div>

      {loading ? (
        <div className="flex justify-center items-center py-12">
          <Loader2 className="h-8 w-8 animate-spin text-purple-600" />
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="bg-white dark:bg-gray-800 p-6 rounded-xl shadow-sm border border-purple-100 dark:border-purple-900/30">
                <h3 className="text-gray-500 dark:text-gray-400 text-sm font-medium">{t('adminPanel.totalStores')}</h3>
                <p className="text-3xl font-bold text-purple-600 dark:text-purple-400 mt-2">{stores.length}</p>
            </div>
            <div className="bg-white dark:bg-gray-800 p-6 rounded-xl shadow-sm border border-green-100 dark:border-green-900/30">
                <h3 className="text-gray-500 dark:text-gray-400 text-sm font-medium">{t('adminPanel.activeSubscriptions')}</h3>
                <p className="text-3xl font-bold text-green-600 dark:text-green-400 mt-2">
                    {stores.filter(s => s.subscription_status === 'active').length}
                </p>
            </div>
            <div className="bg-white dark:bg-gray-800 p-6 rounded-xl shadow-sm border border-red-100 dark:border-red-900/30">
                <h3 className="text-gray-500 dark:text-gray-400 text-sm font-medium">{t('adminPanel.expired')}</h3>
                <p className="text-3xl font-bold text-red-600 dark:text-red-400 mt-2">
                    {stores.filter(s => s.subscription_status === 'expired' || !s.subscription_status).length}
                </p>
            </div>
          </div>

          {stores.length === 0 ? (
            <div className="bg-white dark:bg-gray-800 p-12 rounded-xl shadow-sm border border-gray-100 dark:border-gray-700 text-center">
              <Store className="h-12 w-12 text-gray-400 mx-auto mb-4" />
              <p className="text-gray-500 dark:text-gray-400">{t('adminPanel.noStores')}</p>
            </div>
          ) : (
            <div className="bg-white dark:bg-gray-800 rounded-xl shadow-sm overflow-hidden border border-gray-100 dark:border-gray-700">
              <div className="overflow-x-auto">
                <table className="w-full text-left">
                    <thead className="bg-gray-50 dark:bg-gray-700">
                        <tr>
                            <th className="p-4 font-semibold text-sm text-gray-700 dark:text-gray-300">{t('adminPanel.storeName')}</th>
                            <th className="p-4 font-semibold text-sm text-gray-700 dark:text-gray-300">{t('adminPanel.owner')}</th>
                            <th className="p-4 font-semibold text-sm text-gray-700 dark:text-gray-300">{t('adminPanel.plan')}</th>
                            <th className="p-4 font-semibold text-sm text-gray-700 dark:text-gray-300">{t('adminPanel.expiresAt')}</th>
                            <th className="p-4 font-semibold text-sm text-gray-700 dark:text-gray-300">{t('adminPanel.status')}</th>
                            <th className="p-4 font-semibold text-sm text-gray-700 dark:text-gray-300">{t('common.actions')}</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 dark:divide-gray-700">
                        {stores.map(store => (
                            <tr key={store.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors">
                                <td className="p-4 font-medium text-gray-900 dark:text-white">{store.name}</td>
                                <td className="p-4 text-sm">
                                    {store.owner ? (
                                        <div>
                                            <div className="font-medium text-gray-900 dark:text-white">{store.owner.name}</div>
                                            <div className="text-gray-500 dark:text-gray-400 text-xs">{store.owner.email}</div>
                                        </div>
                                    ) : <span className="text-gray-400">{t('adminPanel.unknown')}</span>}
                                </td>
                                <td className="p-4 text-sm text-gray-700 dark:text-gray-300 capitalize">
                                  {store.subscription_plan === 'monthly' ? t('subscription.monthly') :
                                   store.subscription_plan === '6months' ? t('subscription.sixMonths') :
                                   store.subscription_plan === 'yearly' ? t('subscription.yearly') :
                                   store.subscription_plan || '-'}
                                </td>
                                <td className="p-4 text-sm text-gray-700 dark:text-gray-300">
                                    {store.subscription_expires_at ? new Date(store.subscription_expires_at).toLocaleDateString('ar-SA') : '-'}
                                </td>
                                <td className="p-4">
                                    <span className={`px-3 py-1 rounded-full text-xs font-semibold ${
                                        store.subscription_status === 'active' 
                                          ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400' 
                                          : 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-400'
                                    }`}>
                                        {store.subscription_status === 'active' ? t('status.active') : t('status.expired')}
                                    </span>
                                </td>
                                <td className="p-4">
                                    <div className="flex gap-2">
                                        <Button 
                                            size="sm" 
                                            variant="outline" 
                                            className="text-green-600 border-green-200 hover:bg-green-50 dark:text-green-400 dark:border-green-800 dark:hover:bg-green-900/20"
                                            onClick={() => handleExtendSubscription(store.id, store.subscription_expires_at, 'monthly')}
                                        >
                                            {t('adminPanel.extendMonth')}
                                        </Button>
                                        <Button 
                                            size="sm" 
                                            variant="outline"
                                            className="text-blue-600 border-blue-200 hover:bg-blue-50 dark:text-blue-400 dark:border-blue-800 dark:hover:bg-blue-900/20"
                                            onClick={() => {
                                              const message = `مرحباً، بخصوص متجر "${store.name}" - أود التواصل حول الاشتراك.`;
                                              window.open(`${CONTACT_INFO.WHATSAPP_URL}?text=${encodeURIComponent(message)}`, '_blank');
                                            }}
                                        >
                                            <MessageCircle className="h-3 w-3" />
                                        </Button>
                                    </div>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-md">
            <DialogHeader>
                <DialogTitle>{t('adminPanel.createNewStore')}</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 py-4">
                <div className="p-4 bg-yellow-50 dark:bg-yellow-900/20 text-yellow-800 dark:text-yellow-300 rounded-lg text-sm flex items-start gap-2">
                    <AlertTriangle className="h-5 w-5 shrink-0 mt-0.5" />
                    <p>{t('adminPanel.note')}</p>
                </div>
                <div className="flex gap-2">
                  <Button onClick={() => setDialogOpen(false)} variant="outline" className="flex-1">{t('common.cancel')}</Button>
                  <Button onClick={() => window.open('/register', '_blank')} className="flex-1 bg-purple-600 hover:bg-purple-700 text-white">
                    {t('adminPanel.goToRegister')}
                  </Button>
                </div>
            </div>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default AdminPanel;
