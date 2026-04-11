'use client';

import { RefreshCcw } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { ApiError } from '@/lib/api/client';
import { trackClientEvent } from '@/lib/telemetry/client';
import type { ChatSessionSettings } from '@/lib/types/chat';
import type { Message } from '@/lib/types/message';
import { useUIStore } from '@/lib/store/ui-store';
import { ChatComposer } from '@/features/chat/components/chat-composer';
import { ChatHeader } from '@/features/chat/components/chat-header';
import { ChatTranscript } from '@/features/chat/components/chat-transcript';
import { DegradedState, ErrorState } from '@/components/feedback/states';
import { useChatStream } from '@/features/chat/api/use-chat-stream';
import {
  useArchiveSession,
  useCreateSession,
  useDeleteSession,
  useForkSession,
  useRenameSession,
  useSession,
  useSessions,
  useUpdateSessionSettings,
} from '@/features/sessions/api/use-sessions';
import { ConfirmSessionActionDialog } from '@/features/sessions/components/confirm-session-action-dialog';
import { RenameSessionDialog } from '@/features/sessions/components/rename-session-dialog';
import { SessionSidebar } from '@/features/sessions/components/session-sidebar';
import { ChatSettingsSheet } from '@/features/settings/components/chat-settings-sheet';
import { useRuntimeStatus } from '@/features/settings/api/use-runtime-status';

export function ChatScreen() {
  const t = useTranslations('chat');
  const searchParams = useSearchParams();
  const requestedSessionId = searchParams.get('session');
  const requestedLoadedSkillId = searchParams.get('loadedSkill');
  const [search, setSearch] = useState('');
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(null);
  const [optimisticMessages, setOptimisticMessages] = useState<Message[]>([]);
  const [streamingMessage, setStreamingMessage] = useState('');
  const [renameOpen, setRenameOpen] = useState(false);
  const [archiveOpen, setArchiveOpen] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsError, setSettingsError] = useState<string | null>(null);
  const [composerError, setComposerError] = useState<string | null>(null);
  const [localSettings, setLocalSettings] = useState<ChatSessionSettings>({ model: '', provider: 'unknown', policyPreset: 'safe-chat', memoryMode: 'standard' });

  const sessionsQuery = useSessions(search);
  const runtimeQuery = useRuntimeStatus();
  const createSession = useCreateSession();
  const renameSession = useRenameSession();
  const archiveSession = useArchiveSession();
  const deleteSession = useDeleteSession();
  const forkSession = useForkSession();
  const updateSessionSettings = useUpdateSessionSettings();
  const chatStream = useChatStream();

  const { runEvents, artifacts, addRunEvent, addArtifact, resetRunState, selectArtifact, updateApprovalState, activeSessionId, setActiveSessionId, selectedProfileId, recentlyLoadedSkillIds, sessionLoadedSkillIds } = useUIStore();

  useEffect(() => {
    if (!sessionsQuery.data?.length) return;

    const preferredFromRoute = requestedSessionId && sessionsQuery.data.some((session) => session.id === requestedSessionId) ? requestedSessionId : null;
    const preferredFromStore = activeSessionId && sessionsQuery.data.some((session) => session.id === activeSessionId) ? activeSessionId : null;
    const preferred = preferredFromRoute ?? preferredFromStore ?? sessionsQuery.data[0].id;

    if (!selectedSessionId || (requestedSessionId && selectedSessionId !== requestedSessionId && preferred === requestedSessionId)) {
      setSelectedSessionId(preferred);
    }
  }, [activeSessionId, requestedSessionId, selectedSessionId, sessionsQuery.data]);

  useEffect(() => {
    if (selectedSessionId && sessionsQuery.data && !sessionsQuery.data.some((session) => session.id === selectedSessionId)) {
      setSelectedSessionId(sessionsQuery.data[0]?.id ?? null);
    }
  }, [selectedSessionId, sessionsQuery.data]);

  const sessionQuery = useSession(selectedSessionId);

  useEffect(() => {
    if (selectedSessionId) {
      setActiveSessionId(selectedSessionId);
    }
  }, [selectedSessionId, setActiveSessionId]);

  useEffect(() => {
    if (sessionQuery.data?.settings) {
      setLocalSettings(sessionQuery.data.settings);
      return;
    }
    if (runtimeQuery.data?.modelDefault) {
      setLocalSettings((current) => ({ ...current, model: runtimeQuery.data?.modelDefault || current.model, provider: runtimeQuery.data?.provider || current.provider }));
    }
  }, [runtimeQuery.data?.modelDefault, runtimeQuery.data?.provider, sessionQuery.data?.settings]);

  const messages = useMemo(() => [...(sessionQuery.data?.messages ?? []), ...optimisticMessages], [optimisticMessages, sessionQuery.data?.messages]);

  const runtimeConnected = runtimeQuery.data?.apiReachable ?? false;
  const runtimeInstalled = runtimeQuery.data?.available ?? false;
  const mockMode = runtimeQuery.data?.mockMode ?? false;
  const runtimeUnavailable = runtimeInstalled && !runtimeConnected;
  const controlsDisabled = (runtimeUnavailable && !mockMode) || updateSessionSettings.isPending;
  const activeTitle = sessionQuery.data?.title ?? t('newChat');
  const activeSettings = localSettings;
  const activeProfileLabel = runtimeQuery.data?.activeProfile ?? selectedProfileId ?? 'default';
  const isPersisted = Boolean(selectedSessionId && sessionQuery.data);
  const composerChips = [
    { key: 'model', label: `${t('model')} · ${activeSettings.model || 'default'}` },
    { key: 'tools', label: `${t('tools')} · ${runtimeConnected ? t('toolsLive') : t('toolsDegraded')}` },
    { key: 'profile', label: `${t('profile')} · ${activeProfileLabel}` },
    { key: 'mode', label: `${t('mode')} · ${activeSettings.policyPreset}` },
    { key: 'files', label: `${t('files')} · ${artifacts.length}` },
  ];
  const optimisticSessionLoadedSkillIds = selectedSessionId ? (sessionLoadedSkillIds[selectedSessionId] ?? []) : [];
  const visibleLoadedSkillIds = Array.from(new Set([requestedLoadedSkillId, ...(optimisticSessionLoadedSkillIds ?? []), ...(recentlyLoadedSkillIds ?? []), ...(sessionQuery.data?.loadedSkillIds ?? [])].filter(Boolean) as string[]));
  const runtimeSummary = runtimeConnected
    ? t('talkingToProvider', { provider: activeSettings.provider })
    : mockMode
      ? t('mockModeDescription')
      : runtimeInstalled
        ? t('runtimeDetectedUnreachable')
        : t('runtimeNotDetected');
  const starterPrompts = [
    t('starterPrompt1'),
    t('starterPrompt2'),
    t('starterPrompt3'),
  ];

  const handleOpenSession = (sessionId: string) => {
    setComposerError(null);
    setSettingsError(null);
    resetRunState();
    setOptimisticMessages([]);
    setStreamingMessage('');
    setSelectedSessionId(sessionId);
    setActiveSessionId(sessionId);
  };

  const handleNewChat = async () => {
    setComposerError(null);
    setSettingsError(null);
    resetRunState();
    setSelectedSessionId(null);
    setActiveSessionId(null);
    setOptimisticMessages([]);
    setStreamingMessage('');
  };

  const handleSend = async (message: string, attachmentIds?: string[]) => {
    let sessionId = selectedSessionId;
    if (!sessionId) {
      const created = await createSession.mutateAsync();
      sessionId = created.session.id;
      setSelectedSessionId(sessionId);
      setActiveSessionId(sessionId);
    }

    const optimisticMessage: Message = { id: `optimistic-${Date.now()}`, role: 'user', content: message, createdAt: new Date().toISOString() };

    resetRunState();
    setComposerError(null);
    setOptimisticMessages((current) => [...current, optimisticMessage]);
    setStreamingMessage('');

    let sendFailed = false;
    try {
      await chatStream.mutateAsync({
        sessionId,
        message,
        attachmentIds,
        onEvent: (event) => {
          if (event.type === 'assistant.delta') {
            setStreamingMessage((current) => current + event.delta);
            return;
          }
          addRunEvent(event);
          if (event.type === 'artifact.emitted') {
            addArtifact({ artifactId: event.artifactId, artifactType: event.artifactType, label: event.label, content: event.content });
          }
        },
      });
    } catch (error) {
      sendFailed = true;
      const messageText = error instanceof Error ? error.message : t('unableToSend');
      if (error instanceof ApiError && error.status === 503) {
        setComposerError(t('runtimeApiUnavailable'));
        await Promise.all([sessionQuery.refetch(), sessionsQuery.refetch(), runtimeQuery.refetch()]);
      } else {
        setComposerError(messageText);
      }
      setOptimisticMessages([]);
      setStreamingMessage('');
    }
    // On success, wait for the session refetch to settle before clearing
    // optimistic state so there is no blank flash between clear and refetch.
    if (!sendFailed) {
      await sessionQuery.refetch();
      setOptimisticMessages([]);
      setStreamingMessage('');
    }
  };

  const handleInlineModelChange = async (model: string, provider: string) => {
    if (!selectedSessionId) return;
    const previous = localSettings;
    setSettingsError(null);
    setComposerError(null);
    setLocalSettings((current) => ({ ...current, model, provider }));

    try {
      await updateSessionSettings.mutateAsync({ sessionId: selectedSessionId, settings: { model, provider } });
    } catch (error) {
      setLocalSettings(previous);
      setSettingsError(error instanceof Error ? error.message : t('unableToUpdateSettings'));
    }
  };

  const handleSaveSettings = async (settings: Partial<ChatSessionSettings>) => {
    if (!selectedSessionId) return;
    const previous = localSettings;
    setSettingsError(null);
    setComposerError(null);
    setLocalSettings((current) => ({ ...current, ...settings }));

    try {
      await updateSessionSettings.mutateAsync({ sessionId: selectedSessionId, settings });
      setSettingsOpen(false);
    } catch (error) {
      setLocalSettings(previous);
      setSettingsError(error instanceof Error ? error.message : t('unableToUpdateSettings'));
    }
  };

  return (
    <>
      <div className="grid h-full gap-5 lg:grid-cols-[320px_minmax(0,1fr)]">
        <SessionSidebar
          sessions={sessionsQuery.data ?? []}
          selectedSessionId={selectedSessionId}
          search={search}
          isLoading={sessionsQuery.isLoading}
          onSearchChange={setSearch}
          onNewChat={() => void handleNewChat()}
          onSelectSession={handleOpenSession}
          onResumeSession={handleOpenSession}
        />
        <section className="flex min-w-0 flex-col overflow-hidden rounded-xl border border-border/70 bg-card/60 shadow-[var(--shadow-elevated)]">
          {mockMode ? (
            <div className="border-b border-warning/30 bg-warning/10 px-5 py-3 text-sm text-foreground">
              {t('mockModeBanner')}
            </div>
          ) : null}
          <ChatHeader
            title={activeTitle}
            settings={activeSettings}
            profileLabel={activeProfileLabel}
            loadedSkillIds={visibleLoadedSkillIds}
            runtimeConnected={runtimeConnected}
            controlsDisabled={controlsDisabled}
            isPersisted={isPersisted}
            archived={sessionQuery.data?.archived}
            runtimeSummary={runtimeSummary}
            hasMessages={messages.length > 0}
            onOpenSettings={() => {
              setSettingsError(null);
              setSettingsOpen(true);
            }}
            onRename={() => setRenameOpen(true)}
            onArchive={() => setArchiveOpen(true)}
            onDelete={() => setDeleteOpen(true)}
            onFork={() => {
              if (!selectedSessionId) return;
              void forkSession.mutateAsync(selectedSessionId).then(({ session }) => {
                resetRunState();
                setSearch('');
                setSelectedSessionId(session.id);
                setActiveSessionId(session.id);
                setOptimisticMessages([]);
                setStreamingMessage('');
              });
            }}
            onModelChange={(model, provider) => {
              void handleInlineModelChange(model, provider);
            }}
          />
          <ChatTranscript
            messages={messages}
            runEvents={runEvents}
            artifacts={artifacts}
            streamingMessage={streamingMessage}
            isStreaming={chatStream.isPending}
            isLoading={sessionQuery.isLoading}
            onApprove={(toolCallId) => {
              trackClientEvent('approval.approved', { toolCallId });
              fetch(`/api/runtime/approvals/${toolCallId}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status: 'approved' }) }).catch(() => undefined);
              updateApprovalState(toolCallId, true);
            }}
            onReject={(toolCallId) => {
              trackClientEvent('approval.rejected', { toolCallId });
              fetch(`/api/runtime/approvals/${toolCallId}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status: 'rejected' }) }).catch(() => undefined);
              updateApprovalState(toolCallId, false);
            }}
            onOpenArtifact={(artifactId) => selectArtifact(artifactId)}
          />
          {runtimeUnavailable && !mockMode ? (
            <div className="mx-4 mb-0">
              <DegradedState
                layout="banner"
                title={t('runtimeUnavailable')}
                description={t('runtimeUnavailableDescription')}
                primaryAction={
                  <button type="button" onClick={() => void runtimeQuery.refetch()} className="inline-flex items-center gap-2 rounded-2xl border border-border/70 bg-background/80 px-3 py-2 text-sm font-medium text-foreground">
                    <RefreshCcw className="h-4 w-4" />
                    {t('retryRuntime')}
                  </button>
                }
                secondaryAction={
                  <a href="/settings/health" className="rounded-2xl border border-border/70 bg-background/80 px-3 py-2 text-sm font-medium text-foreground">
                    {t('openDiagnostics')}
                  </a>
                }
              />
            </div>
          ) : null}
          {composerError ? <div className="mx-4 mt-4"><ErrorState error={composerError} layout="banner" /></div> : null}
          {settingsError ? <div className="mx-4 mt-4"><ErrorState error={settingsError} layout="banner" /></div> : null}
          <ChatComposer disabled={chatStream.isPending || (runtimeUnavailable && !mockMode)} statusNote={runtimeUnavailable && !mockMode ? t('runtimeOffline') : mockMode ? t('mockModeActive') : messages.length === 0 ? t('startWithRequest') : t('enterToSend')} chips={composerChips} starterPrompts={messages.length === 0 ? starterPrompts : []} onSend={handleSend} />

        </section>
      </div>

      <RenameSessionDialog
        open={renameOpen}
        initialTitle={activeTitle}
        onClose={() => setRenameOpen(false)}
        onSubmit={async (title) => {
          if (!selectedSessionId) return;
          setRenameOpen(false);
          await renameSession.mutateAsync({ sessionId: selectedSessionId, title });
        }}
      />

      <ConfirmSessionActionDialog open={archiveOpen} title={t('archiveSession')} description={t('archiveSessionDescription')} confirmLabel={t('archive')} onClose={() => setArchiveOpen(false)} onConfirm={async () => {
        if (!selectedSessionId) return;
        await archiveSession.mutateAsync(selectedSessionId);
        setArchiveOpen(false);
      }} />

      <ConfirmSessionActionDialog open={deleteOpen} title={t('deleteSession')} description={t('deleteSessionDescription')} confirmLabel={t('delete')} confirmClassName="rounded-2xl bg-danger px-4 py-2 text-sm font-medium text-white" onClose={() => setDeleteOpen(false)} onConfirm={async () => {
        if (!selectedSessionId) return;
        const deletedId = selectedSessionId;
        await deleteSession.mutateAsync(deletedId);
        resetRunState();
        setDeleteOpen(false);
        if (deletedId === selectedSessionId) {
          setSelectedSessionId(null);
        }
      }} />

      <ChatSettingsSheet open={settingsOpen} settings={activeSettings} saving={updateSessionSettings.isPending} error={settingsError} disabled={runtimeUnavailable && !mockMode} onClose={() => setSettingsOpen(false)} onSave={handleSaveSettings} />
    </>
  );
}
