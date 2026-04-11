'use client';

import Link from 'next/link';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { CardSkeletonGrid } from '@/components/feedback/card-skeleton-grid';
import { DegradedState, EmptyState, ErrorState } from '@/components/feedback/states';
import { useAddMcpExtension, useExtensions } from '@/features/extensions/api/use-extensions';
import { AddMcpServerDialog } from '@/features/extensions/components/add-mcp-server-dialog';
import { ExtensionCard } from '@/features/extensions/components/extension-card';
import { McpHub } from '@/features/extensions/components/mcp-hub';
import { ToolInventory } from '@/features/extensions/components/tool-inventory';
import { McpDiagnosticsPanel } from '@/features/settings/components/mcp-diagnostics';
import { useRuntimeStatus } from '@/features/settings/api/use-runtime-status';
import { describeApprovalPolicy, describeGovernance } from '@/lib/presentation/capability-labels';
import { useUIStore } from '@/lib/store/ui-store';

type ExtensionsTab = 'installed' | 'mcp' | 'tools' | 'approvals' | 'diagnostics' | 'discover';

export function ExtensionsScreen({ initialTab = 'installed' }: { initialTab?: ExtensionsTab }) {
  const router = useRouter();
  const t = useTranslations('extensions');
  const tc = useTranslations('common');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [tab, setTab] = useState<ExtensionsTab>(initialTab);
  const { activeSessionId } = useUIStore();
  const extensionsQuery = useExtensions();
  const runtimeQuery = useRuntimeStatus();
  const addMcp = useAddMcpExtension();
  const extensions = extensionsQuery.data?.extensions ?? [];
  const tools = extensionsQuery.data?.tools ?? [];
  const visibleExtensions = tab === 'mcp' ? extensions.filter((extension) => extension.type === 'mcp') : extensions;
  const approvalGated = extensions.filter((extension) => extension.governance === 'approval-gated' || extension.approvalPolicy !== 'auto');
  const sessionScopedTools = tools.filter((tool) => tool.scope === 'session');
  const profileScopedTools = tools.filter((tool) => tool.scope === 'profile');
  const globalTools = tools.filter((tool) => tool.scope === 'global');
  const needsAttention = extensions.filter((extension) => extension.health !== 'healthy' || extension.authState === 'needs-auth' || extension.authState === 'expired');
  const activeProfileLabel = runtimeQuery.data?.profileContext?.label ?? runtimeQuery.data?.activeProfile ?? t('unknownProfile');

  const tabMeta: Record<ExtensionsTab, { label: string; title: string; description: string }> = {
    installed: {
      label: t('connectedNow'),
      title: t('installedIntegrations'),
      description: t('installedIntegrationsDescription'),
    },
    mcp: {
      label: t('mcpServers'),
      title: t('installedMcpServers'),
      description: t('installedMcpServersDescription'),
    },
    discover: {
      label: t('mcpHub'),
      title: t('discoverMcpServers'),
      description: t('discoverMcpServersDescription'),
    },
    tools: {
      label: t('availableToolsTab'),
      title: t('toolsAgentCanUse'),
      description: t('toolsAgentCanUseDescription'),
    },
    approvals: {
      label: t('approvalRules'),
      title: t('approvalRulesTitle'),
      description: t('approvalRulesDescription'),
    },
    diagnostics: {
      label: t('diagnostics'),
      title: t('diagnosticsTitle'),
      description: t('diagnosticsDescription'),
    },
  };

  const currentTab = tabMeta[tab];

  return (
    <div className="h-full space-y-6 overflow-y-auto p-4 lg:p-6">
      <section className="space-y-4 rounded-3xl border border-border/70 bg-card/60 p-5 shadow-[var(--shadow-elevated)] lg:p-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="max-w-3xl">
            <h1 className="text-2xl font-semibold">{t('title')}</h1>
            <p className="mt-2 text-sm leading-6 text-muted-foreground">
              {t('subtitle')}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setDialogOpen(true)}
              className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
            >
              {t('addMcpServer')}
            </button>
            <Link href="/plugins" className="rounded-lg border border-border/70 bg-background/80 px-4 py-2 text-sm font-medium text-foreground">
              {t('openPlugins')}
            </Link>
          </div>
        </div>

        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
            <p className="text-xs uppercase tracking-label text-muted-foreground">{t('installedNow')}</p>
            <p className="mt-2 text-2xl font-semibold">{extensions.length}</p>
            <p className="mt-1 text-sm text-muted-foreground">{t('installedNowDescription')}</p>
          </div>
          <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
            <p className="text-xs uppercase tracking-label text-muted-foreground">{t('availableTools')}</p>
            <p className="mt-2 text-2xl font-semibold">{tools.length}</p>
            <p className="mt-1 text-sm text-muted-foreground">{t('availableToolsDescription')}</p>
          </div>
          <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
            <p className="text-xs uppercase tracking-label text-muted-foreground">{t('needsAttention')}</p>
            <p className="mt-2 text-2xl font-semibold">{needsAttention.length}</p>
            <p className="mt-1 text-sm text-muted-foreground">{t('needsAttentionDescription')}</p>
          </div>
          <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
            <p className="text-xs uppercase tracking-label text-muted-foreground">{t('activeProfile')}</p>
            <p className="mt-2 text-lg font-semibold">{activeProfileLabel}</p>
            <p className="mt-1 text-sm text-muted-foreground">{t('activeProfileDescription', { count: profileScopedTools.length })}</p>
          </div>
        </div>

        <div className="grid gap-3 lg:grid-cols-3">
          <div className="rounded-2xl border border-border/60 bg-background/70 p-4 text-sm text-muted-foreground shadow-sm">
            <p className="font-medium text-foreground">{t('whatIsIntegration')}</p>
            <p className="mt-2">{t('whatIsIntegrationDescription')}</p>
          </div>
          <div className="rounded-2xl border border-border/60 bg-background/70 p-4 text-sm text-muted-foreground shadow-sm">
            <p className="font-medium text-foreground">{t('whatAreTools')}</p>
            <p className="mt-2">{t('whatAreToolsDescription')}</p>
          </div>
          <div className="rounded-2xl border border-border/60 bg-background/70 p-4 text-sm text-muted-foreground shadow-sm">
            <p className="font-medium text-foreground">{t('wherePluginsFit')}</p>
            <p className="mt-2">{t('wherePluginsFitDescription')}</p>
          </div>
        </div>
      </section>

      <div className="flex flex-wrap gap-2">
        {(Object.entries(tabMeta) as Array<[ExtensionsTab, { label: string; title: string; description: string }]>).map(([key, meta]) => (
          <button
            key={key}
            type="button"
            onClick={() => setTab(key)}
            className={`rounded-lg px-4 py-2 text-sm ${tab === key ? 'bg-primary text-primary-foreground' : 'border border-border text-muted-foreground'}`}
          >
            {meta.label}
          </button>
        ))}
      </div>

      <section className="space-y-4 rounded-2xl border border-border/60 bg-card/55 p-4 shadow-sm">
        <div>
          <h2 className="text-lg font-semibold text-foreground">{currentTab.title}</h2>
          <p className="mt-1 text-sm text-muted-foreground">{currentTab.description}</p>
        </div>

        {runtimeQuery.data?.available && runtimeQuery.data?.apiReachable === false ? (
          <DegradedState
            layout="banner"
            title={t('runtimeDataDegraded')}
            description={t('runtimeDataDegradedDescription')}
          />
        ) : null}

        {extensionsQuery.isLoading ? <CardSkeletonGrid count={3} cardClassName="h-32" /> : null}

        {extensionsQuery.isError ? (
          <ErrorState
            title={t('couldNotLoad')}
            error={extensionsQuery.error}
            description={t('couldNotLoadDescription')}
          />
        ) : null}

        {tab === 'tools' ? (
          <>
            <div className="grid gap-3 md:grid-cols-3">
              <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
                <p className="text-xs uppercase tracking-label text-muted-foreground">{t('availableEverywhere')}</p>
                <p className="mt-2 text-2xl font-semibold">{globalTools.length}</p>
                <p className="mt-1 text-sm text-muted-foreground">{t('availableEverywhereDescription')}</p>
              </div>
              <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
                <p className="text-xs uppercase tracking-label text-muted-foreground">{t('followsProfile')}</p>
                <p className="mt-2 text-2xl font-semibold">{profileScopedTools.length}</p>
                <p className="mt-1 text-sm text-muted-foreground">{t('followsProfileDescription')}</p>
              </div>
              <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
                <p className="text-xs uppercase tracking-label text-muted-foreground">{t('onlyThisChat')}</p>
                <p className="mt-2 text-2xl font-semibold">{sessionScopedTools.length}</p>
                <p className="mt-1 text-sm text-muted-foreground">{activeSessionId ? t('onlyThisChatDescription') : t('onlyThisChatNoSession')}</p>
              </div>
            </div>
            <ToolInventory tools={tools} />
          </>
        ) : null}

        {tab === 'diagnostics' ? <McpDiagnosticsPanel /> : null}

        {tab === 'approvals' ? (
          <div className="space-y-3">
            {approvalGated.map((extension) => (
              <div key={extension.id} className="rounded-xl border border-border bg-card p-4 shadow-sm">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <p className="font-medium">{extension.name}</p>
                  <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
                    <span className="rounded-full border border-border px-2 py-1">{describeGovernance(extension.governance)}</span>
                    <span className="rounded-full border border-border px-2 py-1">{describeApprovalPolicy(extension.approvalPolicy)}</span>
                  </div>
                </div>
                <p className="mt-2 text-sm text-muted-foreground">{extension.description}</p>
              </div>
            ))}
            {approvalGated.length === 0 ? (
              <EmptyState
                layout="banner"
                title={t('noApprovalRules')}
                description={t('noApprovalRulesDescription')}
              />
            ) : null}
          </div>
        ) : null}

        {tab === 'installed' || tab === 'mcp' ? (
          visibleExtensions.length > 0 ? (
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              {visibleExtensions.map((extension) => (
                <ExtensionCard key={extension.id} extension={extension} />
              ))}
            </div>
          ) : (
            <EmptyState
              title={tab === 'mcp' ? t('noMcpServers') : t('noIntegrations')}
              description={
                tab === 'mcp'
                  ? t('noMcpServersDescription')
                  : t('noIntegrationsDescription')
              }
              primaryAction={
                <button type="button" onClick={() => setDialogOpen(true)} className="rounded-2xl bg-primary px-4 py-2 text-sm font-medium text-primary-foreground">
                  {t('addMcpServer')}
                </button>
              }
              secondaryAction={
                <button type="button" onClick={() => setTab('discover')} className="rounded-2xl border border-border/70 bg-background/80 px-4 py-2 text-sm font-medium text-foreground">
                  {t('browseMcpHub')}
                </button>
              }
            />
          )
        ) : null}

        {tab === 'discover' ? <McpHub /> : null}
      </section>

      <AddMcpServerDialog
        open={dialogOpen}
        onClose={() => setDialogOpen(false)}
        onSubmit={async (payload) => {
          const { extension } = await addMcp.mutateAsync(payload);
          setDialogOpen(false);
          router.push(`/extensions/${extension.id}`);
        }}
      />
    </div>
  );
}
