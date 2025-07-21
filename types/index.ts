export type MemoryType = 'personal' | 'health' | 'work' | 'social' | 'preference';

export interface Memory {
  id: string;
  title: string;
  content: string;
  tags: string[];
  type: MemoryType;
  visibility: 'private' | 'public';
  createdAt: string;
  updatedAt: string;
}

export interface PromptLog {
  id: string;
  originalPrompt: string;
  enhancedPrompt: string;
  memoryUsed: string[];
  timestamp: string;
} 