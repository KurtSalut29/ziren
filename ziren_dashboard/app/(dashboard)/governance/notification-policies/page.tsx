'use client';

import { useEffect, useState } from 'react';
import { Save } from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { fetchNotificationPolicies, updateNotificationPolicies } from '@/lib/api/governance';
import { ApiError } from '@/lib/api/client';
import { Button } from '@/components/efferd/ui/button';
import { Switch } from '@/components/efferd/ui/switch';
import { PolicyHistoryCard } from '@/components/governance/policy-history-card';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { useNotice } from '@/lib/toast';

interface NotificationPolicyValue {
  system_alerts: boolean;
  admin_notifications: boolean;
  incident_alerts: boolean;
}

const LABELS: Record<keyof NotificationPolicyValue, string> = {
  system_alerts: 'System alerts (maintenance, outages)',
  admin_notifications: 'Administrative notifications (new accounts, config changes)',
  incident_alerts: 'Incident-related notifications',
};

export default function NotificationPoliciesPage() {
  const { token } = useAuth();
  const [value, setValue] = useState<NotificationPolicyValue | null>(null);
  const [saving, setSaving] = useState(false);
  const setMsg = useNotice();

  useEffect(() => {
    if (!token) return;
    fetchNotificationPolicies(token)
      .then(p => setValue(p.value as unknown as NotificationPolicyValue))
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setMsg({ type: 'error', text: e instanceof Error ? e.message : 'Failed to load.' });
      });
  }, [token, setMsg]);

  async function save() {
    if (!token || !value) return;
    setSaving(true);
    try {
      await updateNotificationPolicies(token, value as unknown as Record<string, unknown>);
      setMsg({ type: 'success', text: 'Notification policies saved.' });
    } catch (e) {
      setMsg({ type: 'error', text: e instanceof Error ? e.message : 'Save failed.' });
    } finally {
      setSaving(false);
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
              <CardTitle className="text-[15px]">Notification Policies</CardTitle>
              <CardDescription>Which categories of system-wide notification are enabled</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              {(Object.keys(LABELS) as (keyof NotificationPolicyValue)[]).map(key => (
                <label className="flex items-center gap-2.5 text-[13px] text-foreground" key={key}>
                  <Switch
                    checked={value[key]}
                    onCheckedChange={c => setValue(v => v && { ...v, [key]: Boolean(c) })}
                  />
                  {LABELS[key]}
                </label>
              ))}
              <Button className="w-fit" disabled={saving} onClick={save} size="sm">
                <Save data-icon="inline-start" />
                {saving ? 'Saving…' : 'Save changes'}
              </Button>
            </CardContent>
          </Card>
          <PolicyHistoryCard policyKey="notification_policies" token={token} />
        </div>
      )}
    </div>
  );
}
