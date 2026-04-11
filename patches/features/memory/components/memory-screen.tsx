'use client';

import { useState } from 'react';
import { useTranslations } from 'next-intl';
import { ContextInspectorPanel } from '@/features/memory/components/context-inspector';
import { MemoryEditor } from '@/features/memory/components/memory-editor';
import { SessionSearchPanel } from '@/features/memory/components/session-search-panel';
import { useContextInspector } from '@/features/memory/api/use-memory';
import { useUIStore } from '@/lib/store/ui-store';

export function MemoryScreen() {
  const [tab, setTab] = useState<'user' | 'agent' | 'search' | 'context'>('user');
  const t = useTranslations('memory');
  const { selectedProfileId, activeSessionId } = useUIStore();
  const contextQuery = useContextInspector(selectedProfileId, activeSessionId);
  const context = contextQuery.data;

  return (
    <div className="h-full overflow-y-auto space-y-6 p-4 lg:p-6">
      <div>
        <h1 className="text-2xl font-semibold">{t('title')}</h1>
        <p className="mt-2 text-sm text-muted-foreground">{t('subtitle')}</p>
      </div>

      <section className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
          <p className="text-xs uppercase tracking-label text-muted-foreground">{t('selectedProfile')}</p>
          <p className="mt-2 font-semibold">{context?.activeProfileId ?? selectedProfileId ?? t('noProfile')}</p>
        </div>
        <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
          <p className="text-xs uppercase tracking-label text-muted-foreground">{t('activeSession')}</p>
          <p className="mt-2 font-semibold">{context?.activeSessionTitle ?? activeSessionId ?? t('noSession')}</p>
        </div>
        <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
          <p className="text-xs uppercase tracking-label text-muted-foreground">{t('loadedSkills')}</p>
          <p className="mt-2 font-semibold">{context?.loadedSkillIds.length ?? 0}</p>
        </div>
        <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
          <p className="text-xs uppercase tracking-label text-muted-foreground">{t('memoryMode')}</p>
          <p className="mt-2 font-semibold">{context?.memoryMode ?? 'standard'}</p>
        </div>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <div className="rounded-2xl border border-border bg-card p-5 shadow-sm text-sm text-muted-foreground">
          <h2 className="text-lg font-semibold text-foreground">{t('memorySemantics')}</h2>
          <div className="mt-4 space-y-3">
            <div className="rounded-xl border border-border bg-background p-4">
              <p className="font-medium text-foreground">{t('userMemory')}</p>
              <p className="mt-1">{t('userMemoryDescription')}</p>
            </div>
            <div className="rounded-xl border border-border bg-background p-4">
              <p className="font-medium text-foreground">{t('agentMemory')}</p>
              <p className="mt-1">{t('agentMemoryDescription')}</p>
            </div>
          </div>
        </div>
        <div className="rounded-2xl border border-border bg-card p-5 shadow-sm text-sm text-muted-foreground">
          <h2 className="text-lg font-semibold text-foreground">{t('importantBehavior')}</h2>
          <div className="mt-4 space-y-3">
            <div className="rounded-xl border border-border bg-background p-4">
              <p className="font-medium text-foreground">{t('editingIsDurable')}</p>
              <p className="mt-1">{t('editingIsDurableDescription')}</p>
            </div>
            <div className="rounded-xl border border-border bg-background p-4">
              <p className="font-medium text-foreground">{t('sessionSearchNotMemory')}</p>
              <p className="mt-1">{t('sessionSearchNotMemoryDescription')}</p>
            </div>
          </div>
        </div>
      </section>

      <div className="flex flex-wrap gap-2">
        {[
          ['user', t('userMemoryTab')],
          ['agent', t('agentMemoryTab')],
          ['search', t('sessionSearch')],
          ['context', t('contextInspector')],
        ].map(([id, label]) => (
          <button key={id} type="button" onClick={() => setTab(id as typeof tab)} className={`rounded-lg px-4 py-2 text-sm ${tab === id ? 'bg-primary text-primary-foreground' : 'border border-border text-muted-foreground'}`}>
            {label}
          </button>
        ))}
      </div>
      {tab === 'user' ? <MemoryEditor scope="user" /> : null}
      {tab === 'agent' ? <MemoryEditor scope="agent" /> : null}
      {tab === 'search' ? <SessionSearchPanel /> : null}
      {tab === 'context' ? <ContextInspectorPanel /> : null}
    </div>
  );
}
