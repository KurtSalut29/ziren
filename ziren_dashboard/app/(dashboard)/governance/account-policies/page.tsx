'use client';

import { useEffect, useState } from 'react';
import { Save } from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { fetchAccountPolicies, updateAccountPolicies } from '@/lib/api/governance';
import { ApiError } from '@/lib/api/client';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { Button } from '@/components/efferd/ui/button';
import { Input } from '@/components/efferd/ui/input';
import { Label } from '@/components/efferd/ui/label';
import { Switch } from '@/components/efferd/ui/switch';
import { PolicyHistoryCard } from '@/components/governance/policy-history-card';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { useNotice } from '@/lib/toast';

interface AccountPolicyValue {
  require_id_verification: boolean;
  auto_suspend_after_inactive_days: number | null;
}

export default function AccountPoliciesPage() {
  const { token } = useAuth();
  const [value, setValue] = useState<AccountPolicyValue | null>(null);
  // The as-loaded value, kept alongside the editable one so a save-click can
  // tell whether it actually touches auto_suspend_after_inactive_days — the
  // one field here with a real operational consequence (it can suspend
  // accounts going forward). Toggling the ID-verification switch alone
  // shouldn't cost the admin a confirmation click.
  const [loadedValue, setLoadedValue] = useState<AccountPolicyValue | null>(null);
  const [saving, setSaving] = useState(false);
  const setMsg = useNotice();
  const [confirmOpen, setConfirmOpen] = useState(false);

  useEffect(() => {
    if (!token) return;
    fetchAccountPolicies(token)
      .then(p => {
        const v = p.value as unknown as AccountPolicyValue;
        setValue(v);
        setLoadedValue(v);
      })
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setMsg({ type: 'error', text: e instanceof Error ? e.message : 'Failed to load.' });
      });
  }, [token, setMsg]);

  async function doSave() {
    if (!token || !value) return;
    setConfirmOpen(false);
    setSaving(true);
    try {
      await updateAccountPolicies(token, value as unknown as Record<string, unknown>);
      setMsg({ type: 'success', text: 'Account policies saved.' });
      setLoadedValue(value);
    } catch (e) {
      setMsg({ type: 'error', text: e instanceof Error ? e.message : 'Save failed.' });
    } finally {
      setSaving(false);
    }
  }

  function handleSaveClick() {
    if (!value) return;
    const autoSuspendChanged = value.auto_suspend_after_inactive_days !== loadedValue?.auto_suspend_after_inactive_days;
    if (autoSuspendChanged) {
      setConfirmOpen(true);
    } else {
      void doSave();
    }
  }

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {!value ? (
        <Skeleton className="h-48 rounded-[var(--radius-card)]" />
      ) : (
        <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader className="gap-1">
              <CardTitle className="text-[15px]">Account Policies</CardTitle>
              <CardDescription>Verification and suspension defaults, province-wide</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              <label className="flex items-center gap-2.5 text-[13px] text-foreground">
                <Switch
                  checked={value.require_id_verification}
                  onCheckedChange={c => setValue(v => v && { ...v, require_id_verification: Boolean(c) })}
                />
                Require ID verification for resident sign-up
              </label>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="auto-suspend">Auto-suspend after inactive (days)</Label>
                <Input
                  id="auto-suspend"
                  onChange={e => setValue(v => v && {
                    ...v,
                    auto_suspend_after_inactive_days: e.target.value ? Number(e.target.value) : null,
                  })}
                  placeholder="Never (leave blank)"
                  type="number"
                  value={value.auto_suspend_after_inactive_days ?? ''}
                />
              </div>
              <Button className="w-fit" disabled={saving} onClick={handleSaveClick} size="sm">
                <Save data-icon="inline-start" />
                {saving ? 'Saving…' : 'Save changes'}
              </Button>
            </CardContent>
          </Card>
          <PolicyHistoryCard policyKey="account_policies" token={token} />
        </div>
      )}

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Save this auto-suspend change?</AlertDialogTitle>
            <AlertDialogDescription>
              {value?.auto_suspend_after_inactive_days
                ? `From now on, any account inactive for ${value.auto_suspend_after_inactive_days} days will be automatically suspended.`
                : 'Auto-suspend will be turned off — inactive accounts will no longer be suspended automatically.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={saving}>Back</AlertDialogCancel>
            <AlertDialogAction disabled={saving} onClick={() => void doSave()}>
              Save changes
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
