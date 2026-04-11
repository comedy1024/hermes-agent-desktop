'use client';

import { useState } from 'react';
import { Puzzle } from 'lucide-react';
import { useTranslations } from 'next-intl';
import { EmptyState, ErrorState, LoadingState } from '@/components/feedback/states';
import { usePlugins, useTogglePlugin, useRemovePlugin } from '@/features/plugins/api/use-plugins';
import { PluginCard } from '@/features/plugins/components/plugin-card';
import { InstallPluginDialog } from '@/features/plugins/components/install-plugin-dialog';

export function PluginsScreen() {
  const t = useTranslations('plugins');
  const pluginsQuery = usePlugins();
  const togglePlugin = useTogglePlugin();
  const removePlugin = useRemovePlugin();
  const [dialogOpen, setDialogOpen] = useState(false);

  const plugins = pluginsQuery.data ?? [];

  function handleToggle(id: string, enabled: boolean) {
    void togglePlugin.mutateAsync({ id, enabled });
  }

  function handleRemove(id: string) {
    void removePlugin.mutateAsync(id);
  }

  return (
    <div className="h-full overflow-y-auto space-y-6 p-4 pb-8 lg:p-6 lg:pb-10">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <h1 className="text-2xl font-semibold">{t('title')}</h1>
          <p className="mt-2 max-w-3xl text-sm text-muted-foreground">
            {t('subtitle')}
          </p>
        </div>
        <button
          type="button"
          onClick={() => setDialogOpen(true)}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
        >
          {t('installPlugin')}
        </button>
      </div>

      <div className="rounded-2xl border border-border/60 bg-card/55 p-4 text-sm text-muted-foreground shadow-sm">
        <p className="font-medium text-foreground">{t('howPluginsDiffer')}</p>
        <p className="mt-2">
          {t('howPluginsDifferDescription')}
        </p>
      </div>

      {pluginsQuery.isLoading ? <LoadingState title={t('loadingTitle')} description={t('loadingDescription')} /> : null}

      {pluginsQuery.isError ? (
        <ErrorState
          title={t('couldNotLoad')}
          error={pluginsQuery.error}
          description={t('couldNotLoadDescription')}
        />
      ) : null}

      {pluginsQuery.isSuccess && plugins.length === 0 ? (
        <EmptyState
          title={t('noPlugins')}
          description={t('noPluginsDescription')}
          icon={<Puzzle className="h-5 w-5" />}
          primaryAction={
            <button
              type="button"
              onClick={() => setDialogOpen(true)}
              className="rounded-2xl bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
            >
              {t('installFirstPlugin')}
            </button>
          }
        />
      ) : null}

      {pluginsQuery.isSuccess && plugins.length > 0 ? (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {plugins.map((plugin) => (
            <PluginCard key={plugin.id} plugin={plugin} onToggle={handleToggle} onRemove={handleRemove} />
          ))}
        </div>
      ) : null}

      <InstallPluginDialog open={dialogOpen} onClose={() => setDialogOpen(false)} />
    </div>
  );
}
