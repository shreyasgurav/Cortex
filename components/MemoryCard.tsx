import { Memory } from "../types";

export default function MemoryCard({ memory, onClick }: { memory: Memory; onClick?: () => void }) {
  return (
    <div
      className="border rounded p-4 mb-2 cursor-pointer hover:bg-gray-50"
      onClick={onClick}
    >
      <div className="flex justify-between items-center">
        <h2 className="text-lg font-semibold">{memory.title}</h2>
        <span className="text-xs bg-gray-200 rounded px-2 py-1">{memory.type}</span>
      </div>
      <div className="text-sm text-gray-600 mt-1">{memory.content.slice(0, 100)}{memory.content.length > 100 ? '...' : ''}</div>
      <div className="mt-2 flex flex-wrap gap-1">
        {memory.tags.map(tag => (
          <span key={tag} className="text-xs bg-blue-100 text-blue-700 rounded px-2 py-0.5">{tag}</span>
        ))}
      </div>
    </div>
  );
} 