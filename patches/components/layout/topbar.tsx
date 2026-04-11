'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { Activity, Menu, PanelRightOpen, Plus, ShieldCheck } from 'lucide-react';
import { ThemeToggle } from '@/components/theme/theme-toggle';
import { ProfileSwitcher } from '@/features/profiles/components/profile-switcher';
import { useRuntimeStatus } from '@/features/settings/api/use-runtime-status';
import { useUIStore } from '@/lib/store/ui-store';
import { cn } from '@/lib/utils';

export function Topbar() {
  const t = useTranslations('topbar');
  const pathname = usePathname();
  const { toggleMobileNav, openRightDrawer, activeSessionId } = useUIStore();
  const runtimeQuery = useRuntimeStatus();
  const runtimeConnected = runtimeQuery.data?.apiReachable ?? false;
  const runtime = runtimeQuery.data;

  const pageMeta: Record<string, { eyebrow: string; title: string; description: string }> = {
    '/': {
      eyebrow: t('workspace'),
      title: t('workspaceTitle'),
      description: t('workspaceDescription'),
    },
    '/chat': {
      eyebrow: t('workspace'),
      title: t('workspaceTitle'),
      description: t('workspaceDescription'),
    },
    '/skills': {
      eyebrow: t('library'),
      title: t('skillsTitle'),
      description: t('skillsDescription'),
    },
    '/extensions': {
      eyebrow: t('extensions'),
      title: t('extensionsTitle'),
      description: t('extensionsDescription'),
    },
    '/memory': {
      eyebrow: t('memory'),
      title: t('memoryTitle'),
      description: t('memoryDescription'),
    },
    '/settings': {
      eyebrow: t('settings'),
      title: t('settingsTitle'),
      description: t('settingsDescription'),
    },
  };

  function resolvePageMeta(pathname: string) {
    if (pathname.startsWith('/settings')) return pageMeta['/settings'];
    return pageMeta[pathname] ?? pageMeta['/'];
  }

  const meta = resolvePageMeta(pathname);

  return (
    <header className="sticky top-0 z-20 border-b border-border/70 bg-background/80 px-3 py-3 backdrop-blur-xl sm:px-4 lg:px-6">
      <div className="flex flex-col gap-3 rounded-xl border border-border/70 card-default px-4 py-3 shadow-[var(--shadow-soft)] lg:flex-row lg:items-center lg:justify-between lg:px-5">
        <div className="flex min-w-0 items-center gap-3">
          <button
            type="button"
            onClick={toggleMobileNav}
            className="rounded-2xl border border-border/70 bg-background/80 p-2 text-muted-foreground shadow-[var(--shadow-card)] lg:hidden"
            aria-label={t('openNavigation')}
          >
            <Menu className="h-4 w-4" />
          </button>
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-[linear-gradient(135deg,hsl(var(--primary)),hsl(var(--accent)))] text-sm font-semibold text-primary-foreground shadow-[var(--shadow-card)]">
            H
          </div>
          <div className="min-w-0 space-y-1">
            <div className="flex flex-wrap items-center gap-2">
              <p className="text-2xs font-semibold uppercase tracking-label text-muted-foreground">{meta.eyebrow}</p>
              <span
                className={cn(
                  'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-2xs font-medium',
                  runtimeConnected ? 'border-success/30 bg-success/10 text-foreground' : 'border-warning/30 bg-warning/10 text-foreground',
                )}
              >
                <Activity className={cn('h-3 w-3', runtimeConnected ? 'text-success' : 'text-warning')} />
                {runtimeConnected ? t('runtimeLive') : t('runtimeDegraded')}
              </span>
              <span className="inline-flex items-center gap-1 rounded-full border border-border/70 bg-background/80 px-2 py-0.5 text-2xs font-medium text-foreground">
                <ShieldCheck className="h-3 w-3 text-approval" />
                {runtime?.profileContext?.label || t('profileContextLoading')}
              </span>
              {activeSessionId ? (
                <span className="inline-flex items-center gap-1 rounded-full border border-border/70 bg-background/80 px-2 py-0.5 text-2xs font-medium text-muted-foreground">
                  {t('savedSession')}
                </span>
              ) : null}
            </div>
            <div className="space-y-0.5">
              <h1 className="truncate text-base font-semibold text-foreground sm:text-lg">{meta.title}</h1>
              <p className="truncate text-sm text-muted-foreground">
                {runtime?.modelDefault
                  ? `${meta.description} ${t('defaultModel')}: ${runtime.modelDefault}${runtime.provider ? ` via ${runtime.provider}` : ''}.`
                  : meta.description}
              </p>
            </div>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2 lg:justify-end">
          <ProfileSwitcher />
          <Link
            href="/chat"
            className="inline-flex items-center gap-2 rounded-2xl border border-border/70 bg-background/80 px-3 py-2 text-sm font-medium text-foreground shadow-[var(--shadow-card)]"
          >
            <Plus className="h-4 w-4" />
            {t('newChat')}
          </Link>
          <span className="hidden h-5 w-px bg-border/70 lg:block" />
          <Link href="/settings/approvals" className="rounded-2xl border border-border/70 bg-background/80 px-3 py-2 text-sm font-medium text-foreground shadow-[var(--shadow-card)]">
            {t('approvals')}
          </Link>
          <Link href="/settings/health" className="rounded-2xl border border-border/70 bg-background/80 px-3 py-2 text-sm font-medium text-foreground shadow-[var(--shadow-card)]">
            {t('diagnostics')}
          </Link>
          <span className="hidden h-5 w-px bg-border/70 lg:block" />
          <button
            type="button"
            onClick={() => openRightDrawer('activity')}
            className="rounded-2xl border border-border/70 bg-background/80 p-2.5 text-muted-foreground shadow-[var(--shadow-card)] transition hover:-translate-y-0.5 hover:bg-card"
            aria-label={t('openInspector')}
          >
            <PanelRightOpen className="h-4 w-4" />
          </button>
          <ThemeToggle />
        </div>
      </div>
    </header>
  );
}
