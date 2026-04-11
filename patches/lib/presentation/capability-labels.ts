import type {
  ExtensionApprovalPolicy,
  ExtensionAuthState,
  ExtensionGovernanceState,
  ExtensionProvenance,
  ExtensionRiskLevel,
} from '@/lib/types/extension';
import type { SkillProvenance, SkillScope } from '@/lib/types/skill';

// Helper to get translations in non-React contexts
// These functions accept an optional translations getter for i18n support
// When called from components, pass the t function from useTranslations('capabilityLabels')

type LabelTranslator = (key: string, params?: Record<string, string | number>) => string;

function defaultT(key: string, params?: Record<string, string | number>): string {
  // Fallback: return the key as-is when no translator is provided
  if (params) {
    return Object.entries(params).reduce((acc, [k, v]) => acc.replace(`{${k}}`, String(v)), key);
  }
  return key;
}

export function describeSkillScope(scope: SkillScope, ownerProfileId?: string | null, t: LabelTranslator = defaultT) {
  if (scope === 'builtin') return t('builtinScope');
  if (scope === 'global') return t('globalScope');
  return ownerProfileId ? t('profileScopedWithId', { id: ownerProfileId }) : t('profileScoped');
}

export function describeSkillProvenance(provenance: SkillProvenance, t: LabelTranslator = defaultT) {
  switch (provenance) {
    case 'built-in':
      return t('official');
    case 'verified':
      return t('verified');
    case 'custom':
      return t('community');
    case 'local-process':
      return t('local');
    default:
      return provenance;
  }
}

export function describeExtensionProvenance(provenance?: ExtensionProvenance | null, t: LabelTranslator = defaultT) {
  switch (provenance) {
    case 'built-in':
      return t('official');
    case 'verified':
      return t('verified');
    case 'custom':
      return t('community');
    case 'self-hosted':
      return t('selfHosted');
    case 'local-process':
      return t('localProcess');
    default:
      return t('unknownSource');
  }
}

export function describeRiskLevel(risk: ExtensionRiskLevel, t: LabelTranslator = defaultT) {
  switch (risk) {
    case 'read':
    case 'low':
      return t('lowRisk');
    case 'write':
    case 'medium':
      return t('writesData');
    case 'execute':
      return t('executesCommands');
    case 'admin':
    case 'high':
      return t('highPrivilege');
    default:
      return risk;
  }
}

export function describeAuthState(authState?: ExtensionAuthState, t: LabelTranslator = defaultT) {
  const value = String(authState ?? 'unknown');

  if (value === 'needs-auth') return t('needsAuth');
  if (value === 'expired') return t('authExpired');
  if (value === 'none') return t('noAuthRequired');
  if (value === 'unknown') return t('authUnknown');
  return t('authConnected');
}

export function describeGovernance(governance?: ExtensionGovernanceState, t: LabelTranslator = defaultT) {
  switch (governance) {
    case 'enabled':
      return t('enabledByPolicy');
    case 'blocked':
      return t('blockedByPolicy');
    case 'approval-gated':
      return t('approvalRequired');
    case 'policy-limited':
      return t('policyLimited');
    default:
      return t('governanceUnknown');
  }
}

export function describeApprovalPolicy(policy?: ExtensionApprovalPolicy, t: LabelTranslator = defaultT) {
  switch (policy) {
    case 'auto':
      return t('autoApprove');
    case 'on-request':
      return t('onRequest');
    case 'always':
      return t('alwaysAsk');
    default:
      return t('policyInherited');
  }
}

export function describeCapabilityScope(scope: 'global' | 'profile' | 'session', t: LabelTranslator = defaultT) {
  switch (scope) {
    case 'global':
      return t('visibleToEveryProfile');
    case 'profile':
      return t('visibleOnlyInProfile');
    case 'session':
      return t('loadedOnlyInSession');
    default:
      return scope;
  }
}
