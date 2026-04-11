'use client';

import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { useProfiles, useUpdateProfile } from '@/features/profiles/api/use-profiles';
import { AuditLog } from '@/features/settings/components/audit-log';
import { PolicyPresetSelector } from '@/features/settings/components/policy-preset-selector';
import { RuntimeStatusPanel } from '@/features/settings/components/runtime-status';
import { useRuntimeStatus } from '@/features/settings/api/use-runtime-status';
import { useUIStore } from '@/lib/store/ui-store';

export function SettingsScreen() {
  const t = useTranslations('settings');
  const { selectedProfileId } = useUIStore();
  const profilesQuery = useProfiles();
  const runtimeQuery = useRuntimeStatus();
  const updateProfile = useUpdateProfile();
  const activeProfile = (profilesQuery.data ?? []).find((profile) => profile.id === selectedProfileId) ?? (profilesQuery.data ?? []).find((profile) => profile.active) ?? (profilesQuery.data ?? [])[0];
  const runtime = runtimeQuery.data;

  const browsers = [
    { href: '/settings/approvals', title: t('browserApprovals'), description: t('browserApprovalsDescription') },
    { href: '/settings/runs', title: t('browserRuns'), description: t('browserRunsDescription') },
    { href: '/settings/telemetry', title: t('browserTelemetry'), description: t('browserTelemetryDescription') },
    { href: '/settings/audit', title: t('browserAudit'), description: t('browserAuditDescription') },
    { href: '/settings/health', title: t('browserHealth'), description: t('browserHealthDescription') },
    { href: '/settings/mcp-diagnostics', title: t('browserMcpDiagnostics'), description: t('browserMcpDiagnosticsDescription') },
    { href: '/settings/artifacts', title: t('browserArtifacts'), description: t('browserArtifactsDescription') },
  ];

  return (
    <div className="h-full overflow-y-auto space-y-6 p-4 lg:p-6">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold">{t('cockpit')}</h1>
        <p className="text-sm text-muted-foreground">{t('cockpitDescription')}</p>
      </div>

      <section className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
        <div className="rounded-2xl border border-border bg-card p-5 shadow-sm">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h2 className="text-lg font-semibold">{t('runtimePosture')}</h2>
              <p className="mt-1 text-sm text-muted-foreground">{t('runtimePostureDescription')}</p>
            </div>
            <div className="grid gap-2 text-sm sm:grid-cols-2">
              <div className="rounded-xl border border-border bg-background px-4 py-3">
                <p className="text-xs uppercase tracking-label text-muted-foreground">{t('connection')}</p>
                <p className="mt-2 font-semibold">{runtime?.apiReachable ? t('runtimeLive') : runtime?.available ? t('runtimeDegraded') : t('runtimeUnavailable')}</p>
              </div>
              <div className="rounded-xl border border-border bg-background px-4 py-3">
                <p className="text-xs uppercase tracking-label text-muted-foreground">{t('profileContext')}</p>
                <p className="mt-2 font-semibold">{runtime?.profileContext?.label ?? runtime?.activeProfile ?? t('loading')}</p>
              </div>
              <div className="rounded-xl border border-border bg-background px-4 py-3">
                <p className="text-xs uppercase tracking-label text-muted-foreground">{t('mcpServers')}</p>
                <p className="mt-2 font-semibold">{runtime?.mcpServers.length ?? 0}</p>
              </div>
              <div className="rounded-xl border border-border bg-background px-4 py-3">
                <p className="text-xs uppercase tracking-label text-muted-foreground">{t('skillsIndexed')}</p>
                <p className="mt-2 font-semibold">{runtime?.skillsCount ?? 0}</p>
              </div>
            </div>
          </div>
          {runtime?.remediationHints?.length ? (
            <div className="mt-4 rounded-xl border border-warning/30 bg-warning/10 p-4 text-sm text-foreground">
              <p className="font-medium">{t('recommendedRemediation')}</p>
              <ul className="mt-2 list-disc space-y-1 pl-5 text-muted-foreground">
                {runtime.remediationHints.slice(0, 4).map((hint) => (
                  <li key={hint}>{hint}</li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>

        {activeProfile ? (
          <section className="rounded-2xl border border-border bg-card p-5 shadow-sm">
            <h2 className="text-lg font-semibold">{t('activeProfilePolicy')}</h2>
            <p className="mt-1 text-sm text-muted-foreground">{t('activeProfilePolicyDescription')}</p>
            <div className="mt-4 space-y-3 text-sm text-muted-foreground">
              <div className="rounded-xl border border-border bg-background px-4 py-3">
                <p className="text-xs uppercase tracking-label text-muted-foreground">{t('selectedProfile')}</p>
                <p className="mt-2 font-semibold text-foreground">{activeProfile.name}</p>
              </div>
              <PolicyPresetSelector
                value={activeProfile.policyPreset ?? 'safe-chat'}
                onChange={(value) => void updateProfile.mutateAsync({ profileId: activeProfile.id, policyPreset: value })}
              />
            </div>
          </section>
        ) : null}
      </section>

      <section className="rounded-2xl border border-border bg-card p-5 shadow-sm">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h2 className="text-lg font-semibold">{t('operationalBrowsers')}</h2>
            <p className="mt-1 text-sm text-muted-foreground">{t('operationalBrowsersDescription')}</p>
          </div>
          <Link href="/settings/health" className="rounded-xl border border-border bg-background px-4 py-2 text-sm font-medium">
            {t('openDiagnosticsFirst')}
          </Link>
        </div>
        <div className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {browsers.map((browser) => (
            <Link key={browser.href} href={browser.href} className="rounded-xl border border-border bg-background p-4 transition hover:bg-muted/40">
              <p className="text-sm font-semibold">{browser.title}</p>
              <p className="mt-2 text-sm text-muted-foreground">{browser.description}</p>
            </Link>
          ))}
        </div>
      </section>

      <RuntimeStatusPanel />
      <AuditLog />
    </div>
  );
}
