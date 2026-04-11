'use client';

import { Bot, FileText, Layers3, Search, Sparkles, TerminalSquare, X } from 'lucide-react';
import { useMemo, type ReactNode } from 'react';
import { useTranslations } from 'next-intl';
import { ArtifactPanel } from '@/features/chat/components/artifact-panel';
import { SourceCard } from '@/features/chat/components/source-card';
import { ToolCard } from '@/features/chat/components/tool-card';
import { useRuntimeArtifacts, useRuntimeTimeline } from '@/features/chat/api/use-runtime-history';
import { useContextInspector } from '@/features/memory/api/use-memory';
import { useRuntimeStatus } from '@/features/settings/api/use-runtime-status';
import { useSession } from '@/features/sessions/api/use-sessions';
import { StatusBadge } from '@/components/feedback/status-badge';
import { useUIStore, type RightDrawerTab } from '@/lib/store/ui-store';
import { governanceTone, humanizeStatus, riskTone, type RiskLevel } from '@/lib/types/runtime-status';
import { cn } from '@/lib/utils';

export function RightDrawer() {
  const t = useTranslations('drawer');
  const {
    rightDrawerOpen,
    closeRightDrawer,
    rightDrawerTab,
    setRightDrawerTab,
    runEvents,
    artifacts,
    selectedArtifactId,
    selectArtifact,
    activeSessionId,
    selectedProfileId,
  } = useUIStore();

  const tabs: Array<{ id: RightDrawerTab; label: string }> = [
    { id: 'context', label: t('overview') },
    { id: 'activity', label: t('activity') },
    { id: 'tools', label: t('tools') },
    { id: 'output', label: t('output') },
    { id: 'session', label: t('thread') },
  ];

  const tabDescriptions: Record<RightDrawerTab, string> = {
    context: t('overviewDescription'),
    activity: t('activityDescription'),
    tools: t('toolsDescription'),
    output: t('outputDescription'),
    session: t('threadDescription'),
  };

  const runtimeTimelineQuery = useRuntimeTimeline(activeSessionId);
  const runtimeArtifactsQuery = useRuntimeArtifacts(activeSessionId);
  const sessionQuery = useSession(activeSessionId);
  const runtimeQuery = useRuntimeStatus();
  const contextQuery = useContextInspector(selectedProfileId, activeSessionId);

  const allEvents = useMemo(() => [...(runtimeTimelineQuery.data ?? []), ...runEvents], [runEvents, runtimeTimelineQuery.data]);
  const displayedArtifacts = useMemo(() => {
    const merged = [...(runtimeArtifactsQuery.data ?? []), ...artifacts];
    return merged.filter((artifact, index) => merged.findIndex((candidate) => candidate.artifactId === artifact.artifactId) === index);
  }, [artifacts, runtimeArtifactsQuery.data]);

  const sourceEvents = allEvents.filter((event) => event.type === 'source.emitted');
  const toolEvents = allEvents.filter((event) => event.type === 'tool.started' || event.type === 'tool.completed');
  const approvalEvents = allEvents.filter((event) => event.type === 'tool.awaiting_approval');
  const phaseEvents = allEvents.filter((event) => event.type === 'run.phase');
  const latestPhase = phaseEvents.at(-1);
  const skillIds = Array.from(
    new Set([...(contextQuery.data?.loadedSkillIds ?? []), ...(sessionQuery.data?.loadedSkillIds ?? [])].filter(Boolean)),
  );
  const toolNames = Array.from(new Set(toolEvents.map((event) => event.toolName)));
  const toolRiskLevels = Array.from(
    new Set(toolEvents.map((event) => event.riskLevel).filter((risk): risk is RiskLevel => Boolean(risk))),
  );

  return (
    <aside
      className={cn(
        'fixed inset-x-3 bottom-3 z-30 flex max-h-[70vh] min-h-[320px] flex-col rounded-xl border border-border/50 bg-card/95 shadow-[var(--shadow-elevated)] backdrop-blur-xl transition-all duration-200 xl:inset-x-auto xl:bottom-auto xl:right-4 xl:top-[calc(1rem+72px)] xl:h-[calc(100vh-5.75rem)] xl:max-h-none xl:w-[360px]',
        rightDrawerOpen ? 'translate-x-0 opacity-100' : 'pointer-events-none translate-x-6 opacity-0',
      )}
    >
      <div className="flex items-start justify-between gap-3 border-b border-border/70 px-4 py-4">
        <div>
          <h2 className="text-base font-semibold text-foreground">{t('inspector')}</h2>
          <p className="mt-1 text-xs leading-5 text-muted-foreground">{tabDescriptions[rightDrawerTab]}</p>
        </div>
        <button
          type="button"
          onClick={closeRightDrawer}
          className="rounded-2xl border border-border/70 bg-background/80 p-2 text-muted-foreground shadow-[var(--shadow-card)]"
          aria-label={t('closeDetailsPanel')}
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      <div className="border-b border-border/60 px-3 py-3">
          <div className="grid grid-cols-5 gap-1 rounded-2xl bg-background/50 p-1">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              type="button"
              onClick={() => setRightDrawerTab(tab.id)}
              className={cn(
                'rounded-[1rem] px-2 py-2 text-xs font-medium text-muted-foreground transition',
                rightDrawerTab === tab.id && 'bg-card/80 text-foreground',
              )}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto px-4 py-4">
        {rightDrawerTab === 'context' ? (
          <div className="space-y-4">
            <Section title={t('currentContext')} description={t('currentContextDescription')}>
              <div className="grid grid-cols-2 gap-3">
                <SummaryMetric label={t('profile')} value={contextQuery.data?.activeProfileId ?? runtimeQuery.data?.activeProfile ?? 'default'} />
                <SummaryMetric label={t('memory')} value={contextQuery.data?.memoryMode ?? sessionQuery.data?.settings.memoryMode ?? 'standard'} />
                <SummaryMetric label={t('policy')} value={contextQuery.data?.policyPreset ?? sessionQuery.data?.settings.policyPreset ?? 'safe-chat'} />
                <SummaryMetric label={t('skills')} value={skillIds.length || t('none')} />
              </div>
              <div className="rounded-2xl border border-border/60 bg-card/50 p-3">
                <p className="text-2xs font-semibold uppercase tracking-label text-muted-foreground">{t('activeThread')}</p>
                <p className="mt-2 text-sm font-semibold text-foreground">{contextQuery.data?.activeSessionTitle ?? sessionQuery.data?.title ?? t('noActiveSession')}</p>
                <p className="mt-1 text-xs leading-5 text-muted-foreground">{contextQuery.data?.activeSessionPreview ?? sessionQuery.data?.preview ?? t('startChatting')}</p>
              </div>
            </Section>

            <Section title={t('loadedSkills')} description={t('loadedSkillsDescription')}>
              {skillIds.length ? (
                <div className="flex flex-wrap gap-2">
                  {skillIds.map((skillId) => (
                    <StatusBadge key={skillId} label={skillId} tone="success" icon={<Sparkles className="h-3.5 w-3.5 text-success" />} />
                  ))}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">{t('noSkillsAttached')}</p>
              )}
            </Section>

            <Section title={t('memorySnippets')} description={t('memorySnippetsDescription')}>
              <div className="grid grid-cols-2 gap-3">
                <SummaryMetric label={t('userMemory')} value={contextQuery.data?.userMemory.length ?? 0} />
                <SummaryMetric label={t('agentMemory')} value={contextQuery.data?.agentMemory.length ?? 0} />
              </div>
              <div className="space-y-2">
                {[...(contextQuery.data?.userMemory ?? []), ...(contextQuery.data?.agentMemory ?? [])].slice(0, 4).map((entry, index) => (
                  <div key={`${entry}-${index}`} className="rounded-2xl border border-border/60 bg-card/50 p-3 text-sm leading-6 text-muted-foreground">
                    {entry}
                  </div>
                ))}
                {!contextQuery.data?.userMemory.length && !contextQuery.data?.agentMemory.length ? (
                  <p className="text-sm text-muted-foreground">{t('noMemorySnippets')}</p>
                ) : null}
              </div>
            </Section>
          </div>
        ) : null}

        {rightDrawerTab === 'activity' ? (
          <div className="space-y-4">
            <Section title={t('whatIsHappening')} description={t('whatIsHappeningDescription')}>
              <div className="grid grid-cols-2 gap-3">
                <SummaryMetric label={t('phase')} value={latestPhase?.label ?? 'Idle'} />
                <SummaryMetric label={t('approvals')} value={approvalEvents.length ? `${approvalEvents.length} ${t('waiting')}` : t('none')} />
              </div>
              <div className="flex flex-wrap gap-2">
                {latestPhase ? <StatusBadge label={latestPhase.phase} tone="accent" /> : <StatusBadge label={t('noActiveRun')} tone="muted" />}
                <StatusBadge label={`${allEvents.length} ${t('events')}`} tone="muted" />
              </div>
            </Section>

            {approvalEvents.length ? (
              <Section title={t('approvalQueue')} description={t('approvalQueueDescription')}>
                <div className="space-y-3">
                  {approvalEvents.map((event) => (
                    <div key={event.toolCallId} className="rounded-2xl border border-approval/35 bg-approval/10 p-3">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <p className="text-sm font-semibold text-foreground">{event.toolName}</p>
                        <div className="flex flex-wrap gap-2">
                          <StatusBadge label={event.governance ?? 'approval-gated'} tone={governanceTone(event.governance ?? 'approval-gated')} />
                          {event.riskLevel ? <StatusBadge label={event.riskLevel} tone={riskTone(event.riskLevel)} /> : null}
                        </div>
                      </div>
                      <p className="mt-2 text-sm leading-6 text-muted-foreground">{event.summary}</p>
                    </div>
                  ))}
                </div>
              </Section>
            ) : null}

            <Section title={t('toolTimeline')} description={t('toolTimelineDescription')}>
              <div className="space-y-3">
                {allEvents.length ? (
                  allEvents
                    .filter((event) => event.type !== 'assistant.delta')
                    .slice(-10)
                    .reverse()
                    .map((event, index) => {
                    if (event.type === 'tool.started' || event.type === 'tool.completed') {
                      return <ToolCard key={`${event.toolCallId}-${event.type}-${index}`} event={event} />;
                    }

                    if (event.type === 'run.phase') {
                      return (
                        <div key={`${event.type}-${event.phase}-${index}`} className="rounded-lg border border-border/70 bg-background/80 p-4 shadow-[var(--shadow-card)]">
                          <div className="flex items-center justify-between gap-3">
                            <div>
                              <p className="text-xs uppercase tracking-label text-muted-foreground">{t('runPhase')}</p>
                              <p className="mt-1 text-sm font-semibold text-foreground">{event.label}</p>
                            </div>
                            <StatusBadge label={humanizeStatus(event.phase)} tone="accent" />
                          </div>
                        </div>
                      );
                    }

                    if (event.type === 'source.emitted') {
                      return (
                        <div key={`${event.type}-${event.source.id}-${index}`} className="rounded-lg border border-border/70 bg-background/80 p-4 shadow-[var(--shadow-card)]">
                          <p className="text-xs uppercase tracking-label text-muted-foreground">{t('sourceCaptured')}</p>
                          <p className="mt-1 text-sm font-semibold text-foreground">{event.source.title}</p>
                          <p className="mt-1 text-xs leading-5 text-muted-foreground">{event.source.snippet}</p>
                        </div>
                      );
                    }

                    if (event.type === 'artifact.emitted') {
                      return (
                        <div key={`${event.type}-${event.artifactId}-${index}`} className="rounded-lg border border-border/70 bg-background/80 p-4 shadow-[var(--shadow-card)]">
                          <p className="text-xs uppercase tracking-label text-muted-foreground">{t('outputCreated')}</p>
                          <p className="mt-1 text-sm font-semibold text-foreground">{event.label}</p>
                          <p className="mt-1 text-xs leading-5 text-muted-foreground">{event.artifactType}</p>
                        </div>
                      );
                    }

                    if (event.type === 'tool.awaiting_approval') {
                      return (
                        <div key={`${event.type}-${event.toolCallId}-${index}`} className="rounded-lg border border-approval/35 bg-approval/10 p-4 shadow-[var(--shadow-card)]">
                          <div className="flex items-center justify-between gap-3">
                            <p className="text-sm font-semibold text-foreground">{event.toolName}</p>
                            <StatusBadge label="approval-gated" tone="warning" />
                          </div>
                          <p className="mt-2 text-sm leading-6 text-muted-foreground">{event.summary}</p>
                        </div>
                      );
                    }

                    if (event.type === 'error') {
                      return (
                        <div key={`${event.type}-${index}`} className="rounded-lg border border-danger/35 bg-danger/8 p-4 shadow-[var(--shadow-card)]">
                          <p className="text-xs uppercase tracking-label text-danger">{t('runtimeError')}</p>
                          <p className="mt-1 text-sm leading-6 text-foreground">{event.message}</p>
                        </div>
                      );
                    }

                    return null;
                  })
                ) : (
                  <p className="text-sm text-muted-foreground">{t('noActivityYet')}</p>
                )}
              </div>
            </Section>
          </div>
        ) : null}

        {rightDrawerTab === 'tools' ? (
          <div className="space-y-4">
            <Section title={t('toolPosture')} description={t('toolPostureDescription')}>
              <div className="grid grid-cols-2 gap-3">
                <SummaryMetric label={t('distinctTools')} value={toolNames.length} />
                <SummaryMetric label={t('artifacts')} value={displayedArtifacts.length} />
              </div>
              <div className="flex flex-wrap gap-2">
                {toolRiskLevels.length ? toolRiskLevels.map((risk) => <StatusBadge key={risk} label={`${risk} risk`} tone={riskTone(risk)} />) : <StatusBadge label={t('readOnlySoFar')} tone="muted" />}
              </div>
            </Section>

            <Section title={t('seenTools')} description={t('seenToolsDescription')}>
              {toolNames.length ? (
                <div className="flex flex-wrap gap-2">
                  {toolNames.map((toolName) => (
                    <StatusBadge key={toolName} label={toolName} tone="accent" icon={<TerminalSquare className="h-3.5 w-3.5 text-accent" />} />
                  ))}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">{t('noToolsExecuted')}</p>
              )}
            </Section>

            <Section title={t('connectedRuntime')} description={t('connectedRuntimeDescription')}>
              <div className="space-y-2">
                {runtimeQuery.data?.mcpServers.length ? (
                  runtimeQuery.data.mcpServers.map((server) => (
                    <div key={server.name} className="rounded-2xl border border-border/70 bg-card/60 p-3">
                      <div className="flex items-center justify-between gap-3">
                        <p className="text-sm font-semibold text-foreground">{server.name}</p>
                        <StatusBadge label={server.url ? 'remote' : 'local'} tone={server.url ? 'success' : 'accent'} />
                      </div>
                      <p className="mt-2 text-xs leading-5 text-muted-foreground">{server.url ?? server.command ?? t('noEndpoint')}</p>
                    </div>
                  ))
                ) : (
                  <p className="text-sm text-muted-foreground">{t('noMcpServers')}</p>
                )}
              </div>
            </Section>
          </div>
        ) : null}

        {rightDrawerTab === 'output' ? (
          <div className="space-y-4">
            <Section title={t('generatedOutput')} description={t('generatedOutputDescription')}>
              <ArtifactPanel artifacts={displayedArtifacts} selectedArtifactId={selectedArtifactId} onSelect={selectArtifact} />
            </Section>
            <Section title={t('sourcesAndCitations')} description={t('sourcesAndCitationsDescription')}>
              <div className="space-y-3">
                {sourceEvents.length ? (
                  sourceEvents.map((event, index) => <SourceCard key={`${event.source.id}-${index}`} source={event.source} />)
                ) : (
                  <p className="text-sm text-muted-foreground">{t('noSourcesEmitted')}</p>
                )}
              </div>
            </Section>
          </div>
        ) : null}

        {rightDrawerTab === 'session' ? (
          <div className="space-y-4">
            <Section title={t('threadSummary')} description={t('threadSummaryDescription')}>
              <div className="rounded-2xl border border-border/60 bg-card/50 p-3">
                <p className="text-2xs uppercase tracking-label text-muted-foreground">{t('title')}</p>
                <p className="mt-2 text-sm font-semibold text-foreground">{sessionQuery.data?.title ?? t('unsavedChat')}</p>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <SummaryMetric label={t('messages')} value={sessionQuery.data?.messages.length ?? 0} />
                <SummaryMetric
                  label={t('updated')}
                  value={sessionQuery.data?.updatedAt ? new Date(sessionQuery.data.updatedAt).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : t('notSaved')}
                />
              </div>
              <div className="flex flex-wrap gap-2">
                <StatusBadge label={sessionQuery.data?.settings.model ?? runtimeQuery.data?.modelDefault ?? t('defaultModel')} tone="accent" icon={<Bot className="h-3.5 w-3.5 text-accent" />} />
                <StatusBadge label={sessionQuery.data?.settings.provider ?? runtimeQuery.data?.provider ?? t('provider')} tone="success" />
                <StatusBadge label={sessionQuery.data?.archived ? t('archived') : t('active')} tone={sessionQuery.data?.archived ? 'muted' : 'success'} />
              </div>
            </Section>

            <Section title={t('threadSettings')} description={t('threadSettingsDescription')}>
              <div className="space-y-2">
                <KeyValueRow label={t('policyPreset')} value={<StatusBadge label={sessionQuery.data?.settings.policyPreset ?? 'safe-chat'} tone="warning" />} />
                <KeyValueRow label={t('memoryMode')} value={<StatusBadge label={sessionQuery.data?.settings.memoryMode ?? 'standard'} tone="muted" />} />
                <KeyValueRow label={t('artifacts')} value={<StatusBadge label={`${displayedArtifacts.length}`} tone="accent" icon={<FileText className="h-3.5 w-3.5 text-accent" />} />} />
                <KeyValueRow label={t('sourcesAndCitations')} value={<StatusBadge label={`${sourceEvents.length}`} tone="success" icon={<Search className="h-3.5 w-3.5 text-success" />} />} />
              </div>
            </Section>

            <Section title={t('workspaceLinkage')} description={t('workspaceLinkageDescription')}>
              <div className="rounded-2xl border border-border/60 bg-card/50 p-3">
                <div className="flex items-center gap-2 text-foreground">
                  <Layers3 className="h-4 w-4 text-accent" />
                  <p className="text-sm font-semibold">{sessionQuery.data?.parentSessionId ? t('forkedThread') : t('primaryThread')}</p>
                </div>
                <p className="mt-2 text-xs leading-5 text-muted-foreground">
                  {sessionQuery.data?.parentSessionId ? t('forkedFrom', { id: sessionQuery.data.parentSessionId }) : t('primarySession')}
                </p>
              </div>
            </Section>
          </div>
        ) : null}
      </div>
    </aside>
  );
}

function Section({ title, description, children }: { title: string; description?: string; children: ReactNode }) {
  return (
    <section className="space-y-3 rounded-2xl border border-border/50 bg-background/35 p-4">
      <div>
        <h3 className="text-sm font-semibold text-foreground">{title}</h3>
        {description ? <p className="mt-1 text-xs leading-5 text-muted-foreground">{description}</p> : null}
      </div>
      {children}
    </section>
  );
}

function SummaryMetric({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="rounded-2xl border border-border/60 bg-card/50 px-3 py-3">
      <p className="text-2xs uppercase tracking-label text-muted-foreground">{label}</p>
      <div className="mt-2 text-sm font-semibold text-foreground">{value}</div>
    </div>
  );
}

function KeyValueRow({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 rounded-2xl border border-border/60 bg-card/50 px-3 py-2.5 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <div className="text-right text-foreground">{value}</div>
    </div>
  );
}
