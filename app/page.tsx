"use client";

import {
  ChangeEvent,
  DragEvent,
  FormEvent,
  PointerEvent as ReactPointerEvent,
  useEffect,
  useMemo,
  useState,
} from "react";

type View =
  | "today"
  | "year"
  | "month"
  | "agenda"
  | "diary"
  | "brief"
  | "settings";
type TaskTag = "工作" | "生活" | "重要";

type Task = {
  id: string;
  title: string;
  date: string;
  start: string;
  end: string;
  tag: TaskTag;
  notes: string;
  done: boolean;
};

type Diary = {
  id: string;
  date: string;
  title: string;
  body: string;
  mood: string;
  updatedAt: number;
};

type ChatMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
};

type MonthNote = {
  month: string;
  content: string;
  updatedAt: number;
};

type PositionedTask = {
  task: Task;
  column: number;
  columns: number;
  startMinutes: number;
  endMinutes: number;
};

type AppData = {
  tasks: Task[];
  monthlyNotes: MonthNote[];
  diaries: Diary[];
  messages: ChatMessage[];
  diaryMessages: ChatMessage[];
  apiKey: string;
};

type CloudState = Omit<AppData, "apiKey">;
type SyncStatus = "local" | "syncing" | "synced" | "needs-login" | "error";

const STORAGE_KEY = "xigua-personal-desk-v1";
const LEGACY_SEED_TASK_IDS = new Set(["seed-1", "seed-2", "seed-3"]);
const DAY_START_MINUTES = 8 * 60;
const DAY_END_MINUTES = 22 * 60;
const HOUR_HEIGHT = 36;
const MIN_TASK_MINUTES = 15;

const pad = (value: number) => String(value).padStart(2, "0");
const toDateKey = (date: Date) =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const todayKey = toDateKey(new Date());
const uid = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;

function shiftDateKey(dateKey: string, amount: number) {
  const date = new Date(`${dateKey}T12:00:00`);
  date.setDate(date.getDate() + amount);
  return toDateKey(date);
}

function startOfWeekKey(dateKey: string) {
  const date = new Date(`${dateKey}T12:00:00`);
  const mondayOffset = (date.getDay() + 6) % 7;
  date.setDate(date.getDate() - mondayOffset);
  return toDateKey(date);
}

function briefTaskLine(task: Task) {
  const notes = task.notes.trim();
  return `${task.title.trim()}${notes ? `：${notes}` : "。"}`;
}

function withoutLegacySeedTasks(tasks: Task[]) {
  return tasks.filter((task) => !LEGACY_SEED_TASK_IDS.has(task.id));
}

function cloudStateFrom(data: AppData): CloudState {
  return {
    tasks: data.tasks,
    monthlyNotes: data.monthlyNotes,
    diaries: data.diaries,
    messages: data.messages,
    diaryMessages: data.diaryMessages,
  };
}

function mergeById<T extends { id: string }>(local: T[], remote: T[]) {
  const merged = new Map<string, T>();
  remote.forEach((item) => merged.set(item.id, item));
  local.forEach((item) => merged.set(item.id, item));
  return Array.from(merged.values());
}

function mergeCloudState(local: CloudState, remote: CloudState): CloudState {
  const notes = new Map(remote.monthlyNotes.map((note) => [note.month, note]));
  local.monthlyNotes.forEach((note) => {
    const current = notes.get(note.month);
    if (!current || note.updatedAt >= current.updatedAt) notes.set(note.month, note);
  });
  return {
    tasks: mergeById(local.tasks, remote.tasks),
    monthlyNotes: Array.from(notes.values()),
    diaries: mergeById(local.diaries, remote.diaries),
    messages: mergeById(local.messages, remote.messages),
    diaryMessages: mergeById(local.diaryMessages, remote.diaryMessages),
  };
}

const seedData: AppData = {
  // 首次打开不放入伪造的个人记录；每一项都应当由用户自己创建。
  tasks: [],
  monthlyNotes: [],
  diaries: [],
  messages: [
    {
      id: "welcome",
      role: "assistant",
      content: "今天想先梳理任务，还是写下一个刚刚发生的瞬间？",
    },
  ],
  diaryMessages: [
    {
      id: "diary-welcome",
      role: "assistant",
      content: "今天发生了什么？说一件具体的事就可以。",
    },
  ],
  apiKey: "",
};

function safeLoad(): AppData {
  if (typeof window === "undefined") return seedData;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return seedData;
    const parsed = JSON.parse(raw) as Partial<AppData>;
    return {
      tasks: Array.isArray(parsed.tasks)
        ? withoutLegacySeedTasks(parsed.tasks as Task[])
        : seedData.tasks,
      monthlyNotes: Array.isArray(parsed.monthlyNotes)
        ? parsed.monthlyNotes as MonthNote[]
        : [],
      diaries: Array.isArray(parsed.diaries) ? parsed.diaries : [],
      messages: Array.isArray(parsed.messages) ? parsed.messages : seedData.messages,
      diaryMessages: Array.isArray(parsed.diaryMessages)
        ? parsed.diaryMessages
        : seedData.diaryMessages,
      apiKey: typeof parsed.apiKey === "string" ? parsed.apiKey : "",
    };
  } catch {
    return seedData;
  }
}

const navItems: { id: View; label: string; hint: string }[] = [
  { id: "today", label: "今天", hint: "此刻" },
  { id: "year", label: "年历", hint: "全年" },
  { id: "month", label: "月历", hint: "全月" },
  { id: "agenda", label: "日程", hint: "一天" },
  { id: "brief", label: "简报", hint: "一周" },
  { id: "diary", label: "日记", hint: "回声" },
  { id: "settings", label: "设置", hint: "本地" },
];

function compareTasks(a: Task, b: Task) {
  const priority = (task: Task) => (task.tag === "重要" ? 0 : 1);
  return (
    Number(a.done) - Number(b.done) ||
    priority(a) - priority(b) ||
    (a.start || "99:99").localeCompare(b.start || "99:99")
  );
}

function timeToMinutes(value: string) {
  const [hours, minutes] = value.split(":").map(Number);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return 0;
  return hours * 60 + minutes;
}

function minutesToTime(value: number) {
  const clamped = Math.max(0, Math.min(DAY_END_MINUTES - 1, value));
  return `${pad(Math.floor(clamped / 60))}:${pad(clamped % 60)}`;
}

function roundToQuarterHour(value: number) {
  return Math.round(value / 15) * 15;
}

function positionOverlappingTasks(tasks: Task[]): PositionedTask[] {
  const normalized = tasks
    .filter((task) => task.start)
    .map((task) => {
      const startMinutes = timeToMinutes(task.start);
      const requestedEnd = task.end ? timeToMinutes(task.end) : startMinutes + 60;
      return {
        task,
        startMinutes,
        endMinutes: Math.max(startMinutes + MIN_TASK_MINUTES, requestedEnd),
      };
    })
    .sort(
      (a, b) =>
        a.startMinutes - b.startMinutes ||
        a.endMinutes - b.endMinutes ||
        a.task.title.localeCompare(b.task.title),
    );

  const positioned: PositionedTask[] = [];
  let group: typeof normalized = [];
  let groupEnd = -1;

  const flushGroup = () => {
    if (!group.length) return;
    const columnEnds: number[] = [];
    const assigned = group.map((item) => {
      let column = columnEnds.findIndex((end) => end <= item.startMinutes);
      if (column === -1) {
        column = columnEnds.length;
        columnEnds.push(item.endMinutes);
      } else {
        columnEnds[column] = item.endMinutes;
      }
      return { ...item, column };
    });
    const columns = Math.max(1, columnEnds.length);
    positioned.push(...assigned.map((item) => ({ ...item, columns })));
    group = [];
    groupEnd = -1;
  };

  normalized.forEach((item) => {
    if (group.length && item.startMinutes >= groupEnd) flushGroup();
    group.push(item);
    groupEnd = Math.max(groupEnd, item.endMinutes);
  });
  flushGroup();

  return positioned;
}

function formatLongDate(dateKey: string) {
  const date = new Date(`${dateKey}T12:00:00`);
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "long",
    day: "numeric",
    weekday: "long",
  }).format(date);
}

function monthDays(cursor: Date) {
  const first = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  const start = new Date(first);
  const mondayIndex = (first.getDay() + 6) % 7;
  start.setDate(first.getDate() - mondayIndex);
  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(start);
    date.setDate(start.getDate() + index);
    return date;
  });
}

function Character() {
  return (
    <div className="character">
      {/* 透明抠图需要保留原始像素边缘，避免运行时图片代理再次压缩。 */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src="/assets/xigua-teacher-user-cutout.png"
        alt="戴西瓜帽、圆框眼镜的西瓜老师"
      />
    </div>
  );
}

export default function Home() {
  const [data, setData] = useState<AppData>(seedData);
  const [hydrated, setHydrated] = useState(false);
  const [view, setView] = useState<View>("today");
  const [selectedDate, setSelectedDate] = useState(todayKey);
  const [monthCursor, setMonthCursor] = useState(
    new Date(new Date().getFullYear(), new Date().getMonth(), 1),
  );
  const [taskModal, setTaskModal] = useState(false);
  const [editingTask, setEditingTask] = useState<Task | null>(null);
  const [diaryDraft, setDiaryDraft] = useState<Diary>({
    id: "",
    date: todayKey,
    title: "",
    body: "",
    mood: "平静",
    updatedAt: 0,
  });
  const [diarySearch, setDiarySearch] = useState("");
  const [diaryInput, setDiaryInput] = useState("");
  const [diaryView, setDiaryView] = useState<"chat" | "draft">("chat");
  const [diaryLength, setDiaryLength] = useState<"简洁" | "长文">("简洁");
  const [isDiaryThinking, setIsDiaryThinking] = useState(false);
  const [todayCapture, setTodayCapture] = useState("");
  const [isTaskExtracting, setIsTaskExtracting] = useState(false);
  const [briefStartDate, setBriefStartDate] = useState(() => startOfWeekKey(todayKey));
  const [briefEndDate, setBriefEndDate] = useState(() =>
    shiftDateKey(startOfWeekKey(todayKey), 6),
  );
  const [briefExtra, setBriefExtra] = useState("");
  const [briefDraft, setBriefDraft] = useState("");
  const [isBriefGenerating, setIsBriefGenerating] = useState(false);
  const [notice, setNotice] = useState("");
  const [syncStatus, setSyncStatus] = useState<SyncStatus>("local");
  const [syncUpdatedAt, setSyncUpdatedAt] = useState(0);
  const [syncReady, setSyncReady] = useState(false);

  useEffect(() => {
    // localStorage 仅在浏览器端可用，因此在首屏挂载后恢复个人数据。
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setData(safeLoad());
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }, [data, hydrated]);

  async function pushCloudState(nextData: AppData, knownUpdatedAt = syncUpdatedAt) {
    const response = await fetch("/api/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        state: cloudStateFrom(nextData),
        clientUpdatedAt: knownUpdatedAt,
      }),
    });
    const payload = (await response.json()) as {
      state?: CloudState | null;
      updatedAt?: number;
      conflict?: boolean;
      error?: string;
    };
    if (response.status === 401) {
      setSyncStatus("needs-login");
      return false;
    }
    if (response.status === 409 && payload.state) {
      const merged = mergeCloudState(cloudStateFrom(nextData), payload.state);
      setData((current) => ({ ...current, ...merged }));
      setSyncUpdatedAt(payload.updatedAt || 0);
      setSyncStatus("synced");
      return false;
    }
    if (!response.ok) throw new Error(payload.error || "同步失败");
    setSyncUpdatedAt(payload.updatedAt || 0);
    setSyncStatus("synced");
    return true;
  }

  async function syncNow() {
    if (!hydrated) return;
    setSyncStatus("syncing");
    try {
      const response = await fetch("/api/sync", { cache: "no-store" });
      const payload = (await response.json()) as {
        state?: CloudState | null;
        updatedAt?: number;
        error?: string;
      };
      if (response.status === 401) {
        setSyncStatus("needs-login");
        setNotice("请先登录 ChatGPT，再回来点击同步。当前设备数据不会丢失。");
        return;
      }
      if (!response.ok) throw new Error(payload.error || "同步失败");
      const local = cloudStateFrom(data);
      const merged = payload.state ? mergeCloudState(local, payload.state) : local;
      const nextData = { ...data, ...merged };
      setData(nextData);
      setSyncUpdatedAt(payload.updatedAt || 0);
      setSyncReady(true);
      await pushCloudState(nextData, payload.updatedAt || 0);
      setNotice(payload.state ? "电脑和手机的数据已合并并同步。" : "已开启云端同步。今后电脑和手机会自动保持一致。");
    } catch {
      setSyncStatus("error");
      setNotice("云端同步暂时不可用，当前仍可继续使用本机数据。");
    }
  }

  useEffect(() => {
    if (!hydrated || !syncReady) return;
    const timer = window.setTimeout(() => {
      void pushCloudState(data).catch(() => setSyncStatus("error"));
    }, 800);
    return () => window.clearTimeout(timer);
    // pushCloudState is defined in the component and intentionally tracks the latest data here.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, hydrated, syncReady]);

  useEffect(() => {
    if (!hydrated) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void syncNow();
    // 只在首次恢复本地数据后尝试一次；匿名访客会自然回到本机模式。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hydrated]);

  const selectedTasks = useMemo(
    () =>
      data.tasks
        .filter((task) => task.date === selectedDate)
        .sort(compareTasks),
    [data.tasks, selectedDate],
  );
  const scheduledSelectedTasks = useMemo(
    () => selectedTasks.filter((task) => Boolean(task.start)),
    [selectedTasks],
  );
  const todayScheduledTasks = useMemo(
    () => selectedTasks.filter((task) => Boolean(task.start)),
    [selectedTasks],
  );
  const positionedTodayTasks = useMemo(
    () => positionOverlappingTasks(todayScheduledTasks),
    [todayScheduledTasks],
  );
  const inboxTasks = useMemo(
    () => data.tasks.filter((task) => !task.start).sort(compareTasks),
    [data.tasks],
  );
  const completedToday = selectedTasks.filter((task) => task.done).length;
  const filteredDiaries = data.diaries
    .filter((diary) =>
      `${diary.title}${diary.body}`.toLowerCase().includes(diarySearch.toLowerCase()),
    )
    .sort((a, b) => b.updatedAt - a.updatedAt);
  const briefNextStartDate = shiftDateKey(briefEndDate, 1);
  const briefNextEndDate = shiftDateKey(briefNextStartDate, 6);
  const briefWeekTasks = useMemo(
    () =>
      data.tasks
        .filter((task) => task.date >= briefStartDate && task.date <= briefEndDate)
        .sort(compareTasks),
    [data.tasks, briefStartDate, briefEndDate],
  );
  const briefNextWeekTasks = useMemo(
    () =>
      data.tasks
        .filter((task) => task.date >= briefNextStartDate && task.date <= briefNextEndDate)
        .sort(compareTasks),
    [data.tasks, briefNextStartDate, briefNextEndDate],
  );

  function updateTask(task: Task) {
    setData((current) => ({
      ...current,
      tasks: current.tasks.some((item) => item.id === task.id)
        ? current.tasks.map((item) => (item.id === task.id ? task : item))
        : [...current.tasks, task],
    }));
  }

  function openTaskDetails(task: Task) {
    setEditingTask({ ...task, date: task.date || todayKey });
    setTaskModal(true);
  }

  function startTaskDrag(event: DragEvent<HTMLElement>, taskId: string) {
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/x-workbench-task", taskId);
  }

  function dropTaskIntoToday(event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    const taskId = event.dataTransfer.getData("text/x-workbench-task");
    const task = data.tasks.find((item) => item.id === taskId);
    if (!task) return;

    const bounds = event.currentTarget.getBoundingClientRect();
    const rawMinutes =
      DAY_START_MINUTES +
      ((event.clientY - bounds.top) / HOUR_HEIGHT) * 60;
    const currentStart = task.start ? timeToMinutes(task.start) : 0;
    const currentEnd = task.end ? timeToMinutes(task.end) : currentStart + 60;
    const duration = task.start
      ? Math.max(MIN_TASK_MINUTES, currentEnd - currentStart)
      : 60;
    const startMinutes = Math.max(
      DAY_START_MINUTES,
      Math.min(
        DAY_END_MINUTES - duration,
        roundToQuarterHour(rawMinutes),
      ),
    );
    const endMinutes = Math.min(DAY_END_MINUTES, startMinutes + duration);

    updateTask({
      ...task,
      date: selectedDate,
      start: minutesToTime(startMinutes),
      end: minutesToTime(endMinutes),
    });
    setNotice(`${task.title} 已安排到 ${minutesToTime(startMinutes)}。`);
  }

  function dropTaskIntoInbox(event: DragEvent<HTMLElement>) {
    event.preventDefault();
    const taskId = event.dataTransfer.getData("text/x-workbench-task");
    const task = data.tasks.find((item) => item.id === taskId);
    if (!task) return;

    updateTask({
      ...task,
      start: "",
      end: "",
    });
    setNotice(`${task.title} 已移回收件箱。`);
  }

  function beginTaskResize(
    event: ReactPointerEvent<HTMLButtonElement>,
    task: Task,
    edge: "start" | "end",
  ) {
    event.preventDefault();
    event.stopPropagation();
    const originY = event.clientY;
    const originStart = timeToMinutes(task.start);
    const originEnd = task.end ? timeToMinutes(task.end) : originStart + 60;

    const onMove = (pointerEvent: PointerEvent) => {
      const delta = roundToQuarterHour(
        ((pointerEvent.clientY - originY) / HOUR_HEIGHT) * 60,
      );
      let nextStart = originStart;
      let nextEnd = originEnd;

      if (edge === "start") {
        nextStart = Math.max(
          DAY_START_MINUTES,
          Math.min(originEnd - MIN_TASK_MINUTES, originStart + delta),
        );
      } else {
        nextEnd = Math.min(
          DAY_END_MINUTES,
          Math.max(originStart + MIN_TASK_MINUTES, originEnd + delta),
        );
      }

      setData((current) => ({
        ...current,
        tasks: current.tasks.map((item) =>
          item.id === task.id
            ? {
                ...item,
                start: minutesToTime(nextStart),
                end: minutesToTime(nextEnd),
              }
            : item,
        ),
      }));
    };

    const onUp = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
    };

    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
  }

  function toggleTask(id: string) {
    setData((current) => ({
      ...current,
      tasks: current.tasks.map((task) =>
        task.id === id ? { ...task, done: !task.done } : task,
      ),
    }));
  }

  function removeTask(id: string) {
    if (!window.confirm("确定删除这项任务吗？")) return false;
    setData((current) => ({
      ...current,
      tasks: current.tasks.filter((task) => task.id !== id),
    }));
    return true;
  }

  function openNewTask(date = selectedDate) {
    setEditingTask({
      id: uid(),
      title: "",
      date,
      start: "",
      end: "",
      tag: "工作",
      notes: "",
      done: false,
    });
    setTaskModal(true);
  }

  function updateMonthNote(month: string, content: string) {
    setData((current) => {
      const existing = current.monthlyNotes.find((note) => note.month === month);
      const nextNote = { month, content, updatedAt: Date.now() };
      return {
        ...current,
        monthlyNotes: existing
          ? current.monthlyNotes.map((note) =>
              note.month === month ? nextNote : note,
            )
          : [...current.monthlyNotes, nextNote],
      };
    });
  }

  function saveDiary() {
    if (!diaryDraft.title.trim() || !diaryDraft.body.trim()) {
      setNotice("先写一个标题和几句话，再保存。");
      return;
    }
    const record = {
      ...diaryDraft,
      id: diaryDraft.id || uid(),
      updatedAt: Date.now(),
    };
    setData((current) => ({
      ...current,
      diaries: current.diaries.some((item) => item.id === record.id)
        ? current.diaries.map((item) => (item.id === record.id ? record : item))
        : [...current.diaries, record],
    }));
    setDiaryDraft(record);
    setNotice("日记已经收好。");
  }

  function deleteDiary(id: string) {
    if (!window.confirm("这篇日记删除后无法恢复，确定删除吗？")) return;
    setData((current) => ({
      ...current,
      diaries: current.diaries.filter((diary) => diary.id !== id),
    }));
    if (diaryDraft.id === id) {
      setDiaryDraft({
        id: "",
        date: todayKey,
        title: "",
        body: "",
        mood: "平静",
        updatedAt: 0,
      });
    }
  }

  async function extractTodayTasks() {
    const value = todayCapture.trim();
    if (!value || isTaskExtracting) return;
    if (!data.apiKey) {
      setView("settings");
      setNotice("先在设置里填入 DeepSeek API Key，AI 才能提取任务。");
      return;
    }
    setIsTaskExtracting(true);
    try {
      const response = await fetch("https://api.deepseek.com/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${data.apiKey}`,
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          temperature: 0.1,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: `把用户写下的内容提取为待办任务。选择的日期是 ${selectedDate}，它是默认日期；但用户明确说出其他日期时必须使用用户说出的日期。例如“2026年8月6日17点汇报工作”应转换为 date="2026-08-06"、start="17:00"。
每项任务标题要简短。明确说出日期时将中文日期转换为 YYYY-MM-DD；明确说出具体时间时转换为 HH:mm。没有明确日期时使用默认日期 ${selectedDate}；没有具体时间时 start 和 end 都为空字符串，任务将进入跨日期收件箱。没有说结束时间时 end 留空。不得猜测或补造日期、时间。tag 只能是 工作、生活、重要。
只输出 JSON：{"tasks":[{"title":"任务标题","date":"YYYY-MM-DD","start":"HH:mm 或空字符串","end":"HH:mm 或空字符串","tag":"工作|生活|重要","notes":"可选补充"}]}。`,
            },
            { role: "user", content: value },
          ],
        }),
      });
      if (!response.ok) throw new Error("DeepSeek 请求失败");
      const result = (await response.json()) as {
        choices?: { message?: { content?: string } }[];
      };
      const raw = result.choices?.[0]?.message?.content?.trim() || "";
      const parsed = JSON.parse(
        raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""),
      ) as { tasks?: Partial<Task>[] };
      const tasks = (Array.isArray(parsed.tasks) ? parsed.tasks : [])
        .filter((task) => task.title?.trim())
        .map((task) => {
          const date = /^\d{4}-\d{2}-\d{2}$/.test(task.date || "")
            ? task.date || selectedDate
            : selectedDate;
          const start = /^\d{2}:\d{2}$/.test(task.start || "") ? task.start || "" : "";
          const end = start && /^\d{2}:\d{2}$/.test(task.end || "") ? task.end || "" : "";
          const tag: TaskTag = ["工作", "生活", "重要"].includes(task.tag || "")
            ? task.tag as TaskTag
            : "工作";
          return {
            id: uid(),
            title: task.title!.trim(),
            date,
            start,
            end,
            tag,
            notes: task.notes?.trim() || "",
            done: false,
          };
        });
      if (!tasks.length) throw new Error("没有可用任务");
      setData((current) => ({ ...current, tasks: [...current.tasks, ...tasks] }));
      setTodayCapture("");
      const inboxCount = tasks.filter((task) => !task.start).length;
      setNotice(
        inboxCount
          ? `已提取 ${tasks.length} 项，其中 ${inboxCount} 项进入收件箱。`
          : `已把 ${tasks.length} 项任务放进 ${selectedDate} 的时间线。`,
      );
    } catch {
      setNotice("这次没有提取成功，请换一种更直接的说法再试。");
    } finally {
      setIsTaskExtracting(false);
    }
  }

  async function sendDiaryMessage() {
    const value = diaryInput.trim();
    if (!value || isDiaryThinking) return;
    if (!data.apiKey) {
      setView("settings");
      setNotice("先在设置里填入 DeepSeek API Key，才能开始对话日记。");
      return;
    }
    const userMessage: ChatMessage = { id: uid(), role: "user", content: value };
    const nextMessages = [...data.diaryMessages, userMessage];
    setData((current) => ({ ...current, diaryMessages: nextMessages }));
    setDiaryInput("");
    setIsDiaryThinking(true);
    try {
      const response = await fetch("https://api.deepseek.com/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${data.apiKey}`,
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          temperature: 0.45,
          messages: [
            {
              role: "system",
              content:
                "你是西瓜老师，帮助用户把今天发生的事聊清楚，之后整理成日记。每次只回复一句简短、具体的话；优先问事情发生了什么、接下来发生了什么或最后结果怎样。除非用户主动提起，否则不要追问感受、意义、成长或内心原因。不要诊断，不要夸奖，不要说教，不要重复用户大段原话。只能使用用户明确说过的信息，不得编造人物、地点、情节、时间、因果或心理活动。",
            },
            ...nextMessages.slice(-16).map(({ role, content }) => ({ role, content })),
          ],
        }),
      });
      if (!response.ok) throw new Error("DeepSeek 请求失败");
      const result = (await response.json()) as {
        choices?: { message?: { content?: string } }[];
      };
      const content =
        result.choices?.[0]?.message?.content?.trim() ||
        "然后发生了什么？";
      setData((current) => ({
        ...current,
        diaryMessages: [
          ...current.diaryMessages,
          { id: uid(), role: "assistant", content },
        ],
      }));
    } catch {
      setNotice("没有连接上 DeepSeek，请检查 API Key 或网络后再试。");
    } finally {
      setIsDiaryThinking(false);
    }
  }

  async function generateDiaryFromConversation() {
    const sourceMessages = data.diaryMessages.filter(
      (message) => message.role === "user",
    );
    if (!sourceMessages.length) {
      setNotice("先聊几句，再生成日记。");
      return;
    }
    if (!data.apiKey) {
      setView("settings");
      setNotice("先在设置里填入 DeepSeek API Key。");
      return;
    }
    setIsDiaryThinking(true);
    try {
      const modeRule =
        diaryLength === "简洁"
          ? "写 3 至 6 个自然段；如果素材很少，就写得更短。"
          : "在素材足够时写 5 至 9 个自然段；素材不足时不要填充或扩写情节。";
      const response = await fetch("https://api.deepseek.com/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${data.apiKey}`,
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          temperature: 0.35,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: `请把下面的对话整理为第一人称中文日记。${modeRule}
只能使用对话中明确出现或可直接推断的信息。不要编造未出现的人物、地点、情节、时间、因果或心理活动。信息不足时宁可写短。语言自然克制，不要鸡汤化。
只输出 JSON：{"title":"24字以内标题","paragraphs":["段落1","段落2"],"takeaway":"30字以内今日所得"}。`,
            },
            {
              role: "user",
              content: data.diaryMessages
                .map(
                  (message) =>
                    `${message.role === "assistant" ? "西瓜老师" : "我"}：${message.content}`,
                )
                .join("\n"),
            },
          ],
        }),
      });
      if (!response.ok) throw new Error("DeepSeek 请求失败");
      const result = (await response.json()) as {
        choices?: { message?: { content?: string } }[];
      };
      const raw = result.choices?.[0]?.message?.content?.trim() || "";
      const jsonText = raw
        .replace(/^```(?:json)?\s*/i, "")
        .replace(/\s*```$/, "");
      const parsed = JSON.parse(jsonText) as {
        title?: string;
        paragraphs?: string[];
        takeaway?: string;
      };
      if (!parsed.title || !Array.isArray(parsed.paragraphs)) {
        throw new Error("无效的日记结构");
      }
      const body = [
        ...parsed.paragraphs.filter(Boolean),
        parsed.takeaway ? `今日所得：${parsed.takeaway}` : "",
      ]
        .filter(Boolean)
        .join("\n\n");
      setDiaryDraft({
        id: "",
        date: selectedDate,
        title: parsed.title,
        body,
        mood: "平静",
        updatedAt: Date.now(),
      });
      setDiaryView("draft");
      setNotice("日记草稿已经生成，请确认修改后再保存。");
    } catch {
      setNotice("这次没有整理成日记，请稍后再试。");
    } finally {
      setIsDiaryThinking(false);
    }
  }

  function exportData() {
    const safeData = { ...data, apiKey: "" };
    const blob = new Blob([JSON.stringify(safeData, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `西瓜老师工作台-${todayKey}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  function importData(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    if (!window.confirm("导入会覆盖当前任务、日记和对话，确定继续吗？")) {
      event.target.value = "";
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const parsed = JSON.parse(String(reader.result)) as Partial<AppData>;
        if (!Array.isArray(parsed.tasks) || !Array.isArray(parsed.diaries)) {
          throw new Error("invalid");
        }
        setData((current) => ({
          tasks: withoutLegacySeedTasks(parsed.tasks as Task[]),
          monthlyNotes: Array.isArray(parsed.monthlyNotes)
            ? parsed.monthlyNotes as MonthNote[]
            : [],
          diaries: parsed.diaries || [],
          messages: Array.isArray(parsed.messages)
            ? parsed.messages
            : seedData.messages,
          diaryMessages: Array.isArray(parsed.diaryMessages)
            ? parsed.diaryMessages
            : seedData.diaryMessages,
          apiKey: current.apiKey,
        }));
        setNotice("数据已导入，API Key 保持不变。");
      } catch {
        setNotice("这个文件不是有效的工作台备份。");
      }
      event.target.value = "";
    };
    reader.readAsText(file);
  }

  const renderToday = () => (
    <main className="content today-page" id="main-content">
      <section className="today-capture">
        <div className="today-capture-copy">
          <div className="today-date-row">
            <p className="eyebrow">{formatLongDate(selectedDate)}</p>
            <div className="today-date-picker">
              <button
                type="button"
                aria-label="前一天"
                onClick={() => shiftDate(-1)}
              >
                ←
              </button>
              <input
                type="date"
                aria-label="选择今天页日期"
                value={selectedDate}
                onChange={(event) => {
                  if (!event.target.value) return;
                  const nextDate = new Date(`${event.target.value}T12:00:00`);
                  setSelectedDate(event.target.value);
                  setMonthCursor(
                    new Date(nextDate.getFullYear(), nextDate.getMonth(), 1),
                  );
                }}
              />
              <button
                type="button"
                aria-label="后一天"
                onClick={() => shiftDate(1)}
              >
                →
              </button>
              <button
                type="button"
                className="today-date-reset"
                onClick={() => {
                  setSelectedDate(todayKey);
                  const now = new Date();
                  setMonthCursor(
                    new Date(now.getFullYear(), now.getMonth(), 1),
                  );
                }}
              >
                今天
              </button>
            </div>
          </div>
          <h1>{selectedDate === todayKey ? "今天要做什么？" : "这一天要做什么？"}</h1>
          <p>直接写下来：有具体时间就安排到日程，没有时间就放进收件箱。</p>
          <div className="today-capture-composer">
            <textarea
              value={todayCapture}
              onChange={(event) => setTodayCapture(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
                  event.preventDefault();
                  void extractTodayTasks();
                }
              }}
              placeholder="例如：上午十点开项目会；整理培训资料；给妈妈回电话"
              aria-label="写下今天要做的事"
            />
            <button
              className="button button--dark"
              disabled={isTaskExtracting || !todayCapture.trim()}
              onClick={() => void extractTodayTasks()}
            >
              {isTaskExtracting ? "正在安排…" : "帮我安排"}
            </button>
          </div>
        </div>
        <Character />
      </section>

      <section className="today-planner-layout">
        <article className="day-planner-card">
          <header className="day-planner-heading">
            <div>
              <p className="eyebrow">从早到晚</p>
              <h2>{selectedDate === todayKey ? "今日日程" : "当日日程"}</h2>
              <span>
                {todayScheduledTasks.length} 项安排 · {completedToday} 项已完成
              </span>
            </div>
            <button className="button button--plain" onClick={() => openNewTask(selectedDate)}>
              安排一件事
            </button>
          </header>
          <div className="day-planner-scroll">
            <div
              className="today-hour-grid"
              onDragOver={(event) => {
                event.preventDefault();
                event.dataTransfer.dropEffect = "move";
              }}
              onDrop={dropTaskIntoToday}
            >
              {Array.from(
                { length: (DAY_END_MINUTES - DAY_START_MINUTES) / 60 },
                (_, index) => {
                  const hour = DAY_START_MINUTES / 60 + index;
                  return (
                    <div className="hour-line" key={hour}>
                      <span>{pad(hour)}:00</span>
                    </div>
                  );
                },
              )}
              <span className="hour-grid-end-label">
                {pad(DAY_END_MINUTES / 60)}:00
              </span>
              <div className="today-task-layer">
                {positionedTodayTasks.map(
                  ({ task, column, columns, startMinutes, endMinutes }) => {
                    const visibleStart = Math.max(startMinutes, DAY_START_MINUTES);
                    const visibleEnd = Math.min(endMinutes, DAY_END_MINUTES);
                    if (visibleEnd <= visibleStart) return null;
                    const top =
                      ((visibleStart - DAY_START_MINUTES) / 60) * HOUR_HEIGHT;
                    const height = Math.max(
                      26,
                      ((visibleEnd - visibleStart) / 60) * HOUR_HEIGHT,
                    );
                    return (
                      <article
                        className={`schedule-block tag-block--${task.tag} ${
                          task.done ? "is-done" : ""
                        }`}
                        draggable
                        key={task.id}
                        onDragStart={(event) => startTaskDrag(event, task.id)}
                        onDoubleClick={(event) => {
                          if ((event.target as HTMLElement).closest("button")) return;
                          openTaskDetails(task);
                        }}
                        title="双击查看任务详情"
                        style={{
                          top: `${top}px`,
                          height: `${height}px`,
                          left: `calc(${(column / columns) * 100}% + 3px)`,
                          width: `calc(${100 / columns}% - 6px)`,
                        }}
                      >
                        <button
                          className="resize-handle resize-handle--top"
                          draggable={false}
                          aria-label={`调整 ${task.title} 的开始时间`}
                          onPointerDown={(event) =>
                            beginTaskResize(event, task, "start")
                          }
                        />
                        <div className="schedule-block-content">
                          <strong title={task.title}>{task.title}</strong>
                        </div>
                        <div className="schedule-block-actions">
                          <button
                            draggable={false}
                            aria-label={`${task.done ? "恢复" : "完成"}：${task.title}`}
                            onPointerDown={(event) => event.stopPropagation()}
                            onClick={() => toggleTask(task.id)}
                          >
                            {task.done ? "↺" : "✓"}
                          </button>
                          <button
                            draggable={false}
                            aria-label={`编辑：${task.title}`}
                            onPointerDown={(event) => event.stopPropagation()}
                            onClick={() => openTaskDetails(task)}
                          >
                            ···
                          </button>
                        </div>
                        <button
                          className="resize-handle resize-handle--bottom"
                          draggable={false}
                          aria-label={`调整 ${task.title} 的结束时间`}
                          onPointerDown={(event) =>
                            beginTaskResize(event, task, "end")
                          }
                        />
                      </article>
                    );
                  },
                )}
              </div>
            </div>
          </div>
        </article>

        <aside
          className="today-inbox-panel"
          onDragOver={(event) => {
            event.preventDefault();
            event.dataTransfer.dropEffect = "move";
          }}
          onDrop={dropTaskIntoInbox}
        >
          <header>
            <div>
              <p className="eyebrow">没有具体时间</p>
              <h2>收件箱 · {inboxTasks.length}</h2>
            </div>
            <button className="text-link" onClick={() => openNewTask(selectedDate)}>
              添加＋
            </button>
          </header>
          <p className="inbox-drag-hint">
            从左侧拖回这里可取消时间；收件箱任务可拖到左侧安排。
          </p>
          <div className="today-inbox-list">
            {inboxTasks.map((task) => (
              <article
                className={task.done ? "is-done" : ""}
                draggable
                key={task.id}
                onDragStart={(event) => startTaskDrag(event, task.id)}
                onDoubleClick={(event) => {
                  if ((event.target as HTMLElement).closest("button")) return;
                  openTaskDetails(task);
                }}
                title="双击查看任务详情"
              >
                <span className="drag-grip" aria-hidden="true">⋮⋮</span>
                <div>
                  <span className={`tag tag--${task.tag}`}>{task.tag}</span>
                  <strong>{task.title}</strong>
                  {task.notes && <small>{task.notes}</small>}
                </div>
                <button
                  draggable={false}
                  aria-label={`编辑：${task.title}`}
                  onClick={() => openTaskDetails(task)}
                >
                  编辑
                </button>
              </article>
            ))}
            {!inboxTasks.length && (
              <div className="inbox-empty">
                <span>✓</span>
                <p>没有待安排的任务。</p>
              </div>
            )}
          </div>
        </aside>
      </section>
    </main>
  );

  const renderYear = () => {
    const year = monthCursor.getFullYear();
    return (
      <main className="content" id="main-content">
        <PageHeader eyebrow="十二个月，一眼看见" title={`${year} 年`} />
        <div className="year-toolbar">
          <button
            className="square-button"
            aria-label="上一年"
            onClick={() => setMonthCursor(new Date(year - 1, 0, 1))}
          >
            ←
          </button>
          <button
            className="button button--plain"
            onClick={() => {
              const now = new Date();
              setMonthCursor(new Date(now.getFullYear(), now.getMonth(), 1));
            }}
          >
            回到今年
          </button>
          <button
            className="square-button"
            aria-label="下一年"
            onClick={() => setMonthCursor(new Date(year + 1, 0, 1))}
          >
            →
          </button>
        </div>
        <section className="year-grid">
          {Array.from({ length: 12 }, (_, monthIndex) => {
            const cursor = new Date(year, monthIndex, 1);
            const days = monthDays(cursor);
            const monthKey = `${year}-${pad(monthIndex + 1)}`;
            const monthNote = data.monthlyNotes.find((note) => note.month === monthKey);
            const monthTaskCount = data.tasks.filter((task) =>
              task.date.startsWith(monthKey) && Boolean(task.start),
            ).length;
            return (
              <article className="year-month" key={monthIndex}>
                <button
                  className="year-month-heading"
                  onClick={() => {
                    setMonthCursor(cursor);
                    setView("month");
                  }}
                >
                  <strong>{monthIndex + 1} 月</strong>
                  {monthTaskCount > 0 && <span>{monthTaskCount} 项任务</span>}
                </button>
                <label className="month-note">
                  <span>这个月要做哪些事？</span>
                  <textarea
                    aria-label={`${year} 年 ${monthIndex + 1} 月的月度计划`}
                    value={monthNote?.content || ""}
                    onChange={(event) => updateMonthNote(monthKey, event.target.value)}
                    placeholder="每行写一件事，不用填具体时间"
                  />
                </label>
                <div className="mini-week">
                  {"一二三四五六日".split("").map((day) => (
                    <span key={day}>{day}</span>
                  ))}
                </div>
                <div className="mini-month-grid">
                  {days.map((date) => {
                    const dateKey = toDateKey(date);
                    const inMonth = date.getMonth() === monthIndex;
                    const dayTaskCount = data.tasks.filter(
                      (task) => task.date === dateKey && Boolean(task.start),
                    ).length;
                    return (
                      <button
                        className={`${inMonth ? "" : "is-muted"} ${
                          dateKey === todayKey ? "is-today" : ""
                        }`}
                        disabled={!inMonth}
                        key={dateKey}
                        aria-label={`${dateKey}${dayTaskCount ? `，${dayTaskCount} 项任务` : ""}`}
                        onClick={() => {
                          setSelectedDate(dateKey);
                          setView("agenda");
                        }}
                      >
                        <span>{date.getDate()}</span>
                        {dayTaskCount > 0 && (
                          <i className={dayTaskCount >= 3 ? "has-many" : ""}>
                            {Math.min(dayTaskCount, 3)}
                          </i>
                        )}
                      </button>
                    );
                  })}
                </div>
              </article>
            );
          })}
        </section>
      </main>
    );
  };

  const renderMonth = () => {
    const days = monthDays(monthCursor);
    const title = `${monthCursor.getFullYear()} 年 ${monthCursor.getMonth() + 1} 月`;
    return (
      <main className="content month-page" id="main-content">
        <PageHeader
          eyebrow="把全月铺开来看"
          title={title}
          actionLabel="新增任务"
          onAction={() => openNewTask(selectedDate)}
        />
        <div className="month-toolbar">
          <button
            className="square-button"
            aria-label="上个月"
            onClick={() =>
              setMonthCursor(
                new Date(monthCursor.getFullYear(), monthCursor.getMonth() - 1, 1),
              )
            }
          >
            ←
          </button>
          <button
            className="button button--plain"
            onClick={() => {
              const now = new Date();
              setMonthCursor(new Date(now.getFullYear(), now.getMonth(), 1));
              setSelectedDate(todayKey);
            }}
          >
            回到本月
          </button>
          <button
            className="square-button"
            aria-label="下个月"
            onClick={() =>
              setMonthCursor(
                new Date(monthCursor.getFullYear(), monthCursor.getMonth() + 1, 1),
              )
            }
          >
            →
          </button>
        </div>
        <section className="calendar-shell">
          <div className="week-row">
            {"一二三四五六日".split("").map((day) => (
              <span key={day}>周{day}</span>
            ))}
          </div>
          <div className="month-grid">
            {days.map((date) => {
              const dateKey = toDateKey(date);
              const dayTasks = data.tasks.filter(
                (task) => task.date === dateKey && Boolean(task.start),
              );
              const inMonth = date.getMonth() === monthCursor.getMonth();
              const selected = dateKey === selectedDate;
              return (
                <button
                  className={`day-cell ${inMonth ? "" : "is-muted"} ${
                    dateKey === todayKey ? "is-today" : ""
                  } ${selected ? "is-selected" : ""}`}
                  key={dateKey}
                  onClick={() => {
                    setSelectedDate(dateKey);
                    setView("agenda");
                  }}
                >
                  <span className="day-number">{date.getDate()}</span>
                  <span className="day-tasks">
                    {dayTasks.slice(0, 10).map((task) => (
                      <span className={`mini-task ${task.done ? "is-done" : ""}`} key={task.id}>
                        {task.title}
                      </span>
                    ))}
                    {dayTasks.length > 10 && <small>还有 {dayTasks.length - 10} 项</small>}
                  </span>
                </button>
              );
            })}
          </div>
        </section>
      </main>
    );
  };

  const renderAgenda = () => (
    <main className="content" id="main-content">
      <PageHeader
        eyebrow="一天只看一天"
        title={formatLongDate(selectedDate)}
        actionLabel="安排一件事"
        onAction={() => openNewTask(selectedDate)}
      />
      <div className="date-stepper">
        <button onClick={() => shiftDate(-1)}>前一天</button>
        <input
          type="date"
          aria-label="选择日程日期"
          value={selectedDate}
          onChange={(event) => setSelectedDate(event.target.value)}
        />
        <button onClick={() => shiftDate(1)}>后一天</button>
        <button
          className="date-today"
          onClick={() => {
            setSelectedDate(todayKey);
            const now = new Date();
            setMonthCursor(new Date(now.getFullYear(), now.getMonth(), 1));
          }}
        >
          回到今天
        </button>
      </div>
      <section className="agenda-layout agenda-layout--tasks-only">
        <div className={`timeline ${scheduledSelectedTasks.length ? "" : "timeline--empty"}`}>
          {scheduledSelectedTasks.length ? (
            scheduledSelectedTasks.map((task) => (
              <article className={`timeline-item ${task.done ? "is-done" : ""}`} key={task.id}>
                <div className="time-column">
                  <strong>{task.start}</strong>
                  <span>{task.end || ""}</span>
                </div>
                <div className="time-pin" />
                <div className="agenda-task" title={task.notes || undefined}>
                  <button
                    className="check check--small"
                    aria-label={`${task.done ? "取消完成" : "完成"}：${task.title}`}
                    onClick={() => toggleTask(task.id)}
                  >
                    {task.done ? "✓" : ""}
                  </button>
                  <span className={`tag tag--${task.tag}`}>{task.tag}</span>
                  <h3>{task.title}</h3>
                  <button
                    className="agenda-edit"
                    onClick={() => {
                      setEditingTask(task);
                      setTaskModal(true);
                    }}
                  >
                    编辑
                  </button>
                  <button className="agenda-delete" onClick={() => removeTask(task.id)}>
                    删除
                  </button>
                </div>
              </article>
            ))
          ) : (
            <EmptyState text="这一天的时间线还是空的。" action={() => openNewTask(selectedDate)} />
          )}
        </div>
      </section>
    </main>
  );

  function shiftDate(amount: number) {
    const date = new Date(`${selectedDate}T12:00:00`);
    date.setDate(date.getDate() + amount);
    setSelectedDate(toDateKey(date));
    setMonthCursor(new Date(date.getFullYear(), date.getMonth(), 1));
  }

  function localBrief(tasks: Task[], nextTasks: Task[]) {
    const currentLines = tasks.length
      ? tasks.map((task) => briefTaskLine(task))
      : ["暂无记录。"];
    const nextLines = nextTasks.length
      ? nextTasks.map((task) => briefTaskLine(task))
      : ["暂无计划。"];
    return [
      "【本周周报】",
      "",
      ...currentLines.map((line, index) => `${index + 1}. ${line}`),
      "",
      "【下周计划】",
      "",
      ...nextLines.map((line, index) => `${index + 1}. ${line}`),
    ].join("\n");
  }

  async function generateBrief() {
    if (briefEndDate < briefStartDate) {
      setNotice("结束日期需要晚于开始日期。");
      return;
    }
    setIsBriefGenerating(true);
    const serializeTasks = (tasks: Task[]) =>
      tasks.map((task) => ({
        title: task.title,
        date: task.date,
        start: task.start,
        end: task.end,
        tag: task.tag,
        notes: task.notes,
        done: task.done,
      }));
    const fallback = localBrief(briefWeekTasks, briefNextWeekTasks);

    if (!data.apiKey) {
      setBriefDraft(fallback);
      setIsBriefGenerating(false);
      setNotice("已按任务生成简报，可以继续修改。若需 AI 归纳，请先配置 DeepSeek Key。");
      return;
    }

    try {
      const response = await fetch("https://api.deepseek.com/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${data.apiKey}`,
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          temperature: 0.2,
          messages: [
            {
              role: "system",
              content: [
                "你是一个克制、准确的工作简报助手。请根据用户提供的任务资料生成一份中文简报。",
                "严格只输出以下格式，不要增加开场白、总结或其他标题：",
                "【本周周报】",
                "",
                "1. 事项：具体进展或动作。",
                "2. 事项：具体进展或动作。",
                "",
                "【下周计划】",
                "",
                "1. 计划事项",
                "2. 计划事项",
                "",
                "只整理资料中出现的内容，不得编造人物、公司、地点、进展或原因。每个事项尽量合并相关任务，表达简洁、适合直接发给同事。",
              ].join("\n"),
            },
            {
              role: "user",
              content: [
                `本周日期：${briefStartDate} 至 ${briefEndDate}`,
                `下周日期：${briefNextStartDate} 至 ${briefNextEndDate}`,
                "",
                "本周任务：",
                JSON.stringify(serializeTasks(briefWeekTasks), null, 2),
                "",
                "下周任务：",
                JSON.stringify(serializeTasks(briefNextWeekTasks), null, 2),
                "",
                "补充素材：",
                briefExtra.trim() || "无",
              ].join("\n"),
            },
          ],
        }),
      });
      if (!response.ok) throw new Error("DeepSeek 请求失败");
      const result = (await response.json()) as {
        choices?: { message?: { content?: string } }[];
      };
      const raw = result.choices?.[0]?.message?.content?.trim() || "";
      const cleaned = raw
        .replace(/^```(?:text|markdown)?\s*/i, "")
        .replace(/\s*```$/, "")
        .trim();
      if (!cleaned.includes("【本周周报】") || !cleaned.includes("【下周计划】")) {
        throw new Error("简报格式不完整");
      }
      setBriefDraft(cleaned);
      setNotice("简报已经生成，可以继续修改后复制。");
    } catch {
      setBriefDraft(fallback);
      setNotice("AI 生成没有完成，已先按任务生成一版简报。");
    } finally {
      setIsBriefGenerating(false);
    }
  }

  async function copyBrief() {
    if (!briefDraft.trim()) return;
    try {
      await navigator.clipboard.writeText(briefDraft);
      setNotice("简报已复制。");
    } catch {
      setNotice("复制没有成功，请直接选中简报文字复制。");
    }
  }

  function shiftBriefWeek(amount: number) {
    setBriefStartDate((current) => shiftDateKey(current, amount * 7));
    setBriefEndDate((current) => shiftDateKey(current, amount * 7));
  }

  const renderDiary = () => (
    <main className="content diary-page" id="main-content">
      <PageHeader
        eyebrow="像聊天一样记录"
        title={diaryView === "chat" ? "对话日记" : "日记草稿"}
        actionLabel={diaryView === "chat" ? "新建对话" : "返回对话"}
        onAction={() => {
          if (diaryView === "draft") {
            setDiaryView("chat");
            return;
          }
          if (
            data.diaryMessages.length > 1 &&
            !window.confirm("开始新对话会清空当前日记对话，确定继续吗？")
          ) {
            return;
          }
          setData((current) => ({
            ...current,
            diaryMessages: seedData.diaryMessages,
          }));
        }}
      />
      <section className="diary-layout diary-layout--conversation">
        <aside className="diary-shelf">
          <div className="shelf-heading">
            <div>
              <span>往日回声</span>
              <strong>{data.diaries.length} 篇</strong>
            </div>
          </div>
          <label className="search-field">
            <span>搜索日记</span>
            <input
              value={diarySearch}
              onChange={(event) => setDiarySearch(event.target.value)}
              placeholder="输入一个词"
            />
          </label>
          <div className="diary-history">
            {filteredDiaries.length ? (
              filteredDiaries.map((diary) => (
                <button
                  className={`diary-row ${diary.id === diaryDraft.id ? "is-active" : ""}`}
                  key={diary.id}
                  onClick={() => {
                    setDiaryDraft(diary);
                    setDiaryView("draft");
                  }}
                >
                  <span>{new Date(`${diary.date}T12:00:00`).getDate()}</span>
                  <div>
                    <strong>{diary.title}</strong>
                    <small>{diary.body.slice(0, 34)}</small>
                  </div>
                </button>
              ))
            ) : (
              <p className="empty-copy">还没有往日回声。</p>
            )}
          </div>
        </aside>

        {diaryView === "chat" ? (
          <article className="diary-chat-shell">
            <div className="message-list diary-message-list" aria-live="polite">
              {data.diaryMessages.map((message) => (
                <div className={`message message--${message.role}`} key={message.id}>
                  {message.role === "user" && <span>我</span>}
                  <p>{message.content}</p>
                </div>
              ))}
              {isDiaryThinking && (
                <div className="thinking">正在整理……</div>
              )}
            </div>
            <div className="diary-chat-tools">
              <label>
                <span>生成长度</span>
                <select
                  value={diaryLength}
                  onChange={(event) =>
                    setDiaryLength(event.target.value as "简洁" | "长文")
                  }
                >
                  <option>简洁</option>
                  <option>长文</option>
                </select>
              </label>
              <button
                className="button button--dark"
                disabled={isDiaryThinking}
                onClick={() => void generateDiaryFromConversation()}
              >
                生成日记
              </button>
              <button
                className="button button--plain danger"
                onClick={() => {
                  if (!window.confirm("是否要清空当前日记对话？")) return;
                  setData((current) => ({
                    ...current,
                    diaryMessages: seedData.diaryMessages,
                  }));
                }}
              >
                清空对话
              </button>
            </div>
            <div className="chat-composer diary-composer">
              <textarea
                value={diaryInput}
                onChange={(event) => setDiaryInput(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && !event.shiftKey) {
                    event.preventDefault();
                    void sendDiaryMessage();
                  }
                }}
                placeholder="写下今天发生的一件事"
                aria-label="写下今天想说的话"
              />
              <button
                className="button button--dark"
                disabled={isDiaryThinking || !diaryInput.trim()}
                onClick={() => void sendDiaryMessage()}
              >
                发送
              </button>
            </div>
          </article>
        ) : (
          <article className="diary-paper">
            <div className="diary-meta">
              <input
                type="date"
                aria-label="日记日期"
                value={diaryDraft.date}
                onChange={(event) =>
                  setDiaryDraft((draft) => ({ ...draft, date: event.target.value }))
                }
              />
              <select
                aria-label="今天的心情"
                value={diaryDraft.mood}
                onChange={(event) =>
                  setDiaryDraft((draft) => ({ ...draft, mood: event.target.value }))
                }
              >
                {["平静", "开心", "疲惫", "期待", "有点乱"].map((mood) => (
                  <option key={mood}>{mood}</option>
                ))}
              </select>
            </div>
            <input
              className="diary-title"
              aria-label="日记标题"
              value={diaryDraft.title}
              onChange={(event) =>
                setDiaryDraft((draft) => ({ ...draft, title: event.target.value }))
              }
              placeholder="给今天起一个标题"
            />
            <textarea
              className="diary-body"
              aria-label="日记正文"
              value={diaryDraft.body}
              onChange={(event) =>
                setDiaryDraft((draft) => ({ ...draft, body: event.target.value }))
              }
              placeholder="对话整理出的日记会出现在这里。"
            />
            <div className="diary-actions">
              <span>这是草稿，只有点击保存后才会进入往日回声</span>
              <div>
                {diaryDraft.id && (
                  <button
                    className="button button--plain danger"
                    onClick={() => deleteDiary(diaryDraft.id)}
                  >
                    删除
                  </button>
                )}
                <button className="button button--plain" onClick={() => setDiaryView("chat")}>
                  返回对话
                </button>
                <button className="button button--dark" onClick={saveDiary}>
                  保存日记
                </button>
              </div>
            </div>
          </article>
        )}
      </section>
    </main>
  );

  const renderBrief = () => (
    <main className="content brief-page" id="main-content">
      <PageHeader
        eyebrow="把一周收拢成几句话"
        title="生成简报"
        actionLabel={isBriefGenerating ? "正在生成…" : "生成简报"}
        onAction={() => void generateBrief()}
      />
      <section className="brief-range-card">
        <div>
          <p className="eyebrow">选择时间范围</p>
          <h2>{briefStartDate} 至 {briefEndDate}</h2>
          <span>下周计划自动取结束日期之后的 7 天。</span>
        </div>
        <div className="brief-range-controls">
          <button type="button" aria-label="上一周" onClick={() => shiftBriefWeek(-1)}>←</button>
          <label>
            <span>开始</span>
            <input
              type="date"
              aria-label="简报开始日期"
              value={briefStartDate}
              onChange={(event) => {
                if (!event.target.value) return;
                setBriefStartDate(event.target.value);
                setBriefEndDate(shiftDateKey(event.target.value, 6));
              }}
            />
          </label>
          <span className="brief-range-separator">至</span>
          <label>
            <span>结束</span>
            <input
              type="date"
              aria-label="简报结束日期"
              value={briefEndDate}
              onChange={(event) => {
                if (event.target.value) setBriefEndDate(event.target.value);
              }}
            />
          </label>
          <button type="button" aria-label="下一周" onClick={() => shiftBriefWeek(1)}>→</button>
        </div>
      </section>
      <section className="brief-layout">
        <article className="brief-material-card">
          <div className="brief-card-heading">
            <div>
              <p className="eyebrow">生成依据</p>
              <h2>本周发生了什么？</h2>
            </div>
            <span className="brief-count-badge">{briefWeekTasks.length} 项</span>
          </div>
          <div className="brief-count-grid">
            <div>
              <span>本周任务</span>
              <strong>{briefWeekTasks.length}</strong>
            </div>
            <div>
              <span>下周任务</span>
              <strong>{briefNextWeekTasks.length}</strong>
            </div>
          </div>
          <label className="field brief-extra-field">
            <span>补充素材（可选）</span>
            <textarea
              value={briefExtra}
              onChange={(event) => setBriefExtra(event.target.value)}
              placeholder="补充任务里没有写到的进展、背景或下周安排"
            />
          </label>
          <p className="brief-hint">
            简报会读取选中日期范围内的任务；没有具体时间的收件箱任务也会被纳入。
          </p>
        </article>
        <article className="brief-output-card">
          <div className="brief-card-heading">
            <div>
              <p className="eyebrow">可编辑结果</p>
              <h2>简报内容</h2>
            </div>
            <span>生成后可直接修改</span>
          </div>
          <textarea
            className="brief-output"
            value={briefDraft}
            onChange={(event) => setBriefDraft(event.target.value)}
            placeholder="点击右上角“生成简报”，这里会出现：\n\n【本周周报】\n\n1. ……\n\n【下周计划】\n\n1. ……"
            aria-label="简报内容"
          />
          <div className="brief-actions">
            <button
              type="button"
              className="button button--plain"
              disabled={!briefDraft.trim()}
              onClick={() => void copyBrief()}
            >
              复制简报
            </button>
            <button
              type="button"
              className="button button--dark"
              disabled={isBriefGenerating}
              onClick={() => void generateBrief()}
            >
              {isBriefGenerating ? "正在生成…" : "重新生成"}
            </button>
          </div>
        </article>
      </section>
    </main>
  );

  const renderSettings = () => (
    <main className="content content--narrow" id="main-content">
      <PageHeader eyebrow="安静地配置一次" title="设置" />
      <section className="settings-stack">
        <article className="setting-card setting-card--sync">
          <p className="eyebrow">跨设备同步</p>
          <h2>电脑和手机保持一致</h2>
          <p>
            登录 ChatGPT 后，任务、收件箱、月历备注、日记和简报会自动保存到云端。首次连接会合并当前设备与云端内容，DeepSeek API Key 仍只保存在本机。
          </p>
          <p className="sync-status" aria-live="polite">
            {syncStatus === "synced" && "已同步"}
            {syncStatus === "syncing" && "正在同步…"}
            {syncStatus === "needs-login" && "请先登录 ChatGPT"}
            {syncStatus === "error" && "同步暂时不可用，当前使用本机数据"}
            {syncStatus === "local" && "当前为本机模式"}
            {syncUpdatedAt > 0 && syncStatus === "synced" && ` · ${new Date(syncUpdatedAt).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })}`}
          </p>
          <div className="row-actions">
            <button className="button button--dark" onClick={() => void syncNow()} disabled={syncStatus === "syncing"}>
              {syncStatus === "syncing" ? "同步中…" : "立即同步"}
            </button>
            <a className="button button--plain" href="/signin-with-chatgpt?return_to=/">
              登录 ChatGPT
            </a>
          </div>
        </article>
        <article className="setting-card">
          <p className="eyebrow">AI 连接</p>
          <h2>DeepSeek API Key</h2>
          <p>
            密钥仅保存在当前浏览器，不会出现在导出的备份里。浏览器端调用仍可能受网络和浏览器安全策略影响。
          </p>
          <label className="field">
            <span>API Key</span>
            <input
              type="password"
              autoComplete="off"
              value={data.apiKey}
              onChange={(event) =>
                setData((current) => ({ ...current, apiKey: event.target.value }))
              }
              placeholder="sk-..."
            />
          </label>
          <div className="row-actions">
            <button
              className="button button--dark"
              onClick={() => setNotice(data.apiKey ? "API Key 已保存在当前浏览器。" : "还没有填入 API Key。")}
            >
              保存设置
            </button>
            {data.apiKey && (
              <button
                className="button button--plain danger"
                onClick={() => {
                  if (!window.confirm("确定删除已保存的 API Key 吗？")) return;
                  setData((current) => ({ ...current, apiKey: "" }));
                }}
              >
                删除密钥
              </button>
            )}
          </div>
        </article>
        <article className="setting-card">
          <p className="eyebrow">本地数据</p>
          <h2>备份与恢复</h2>
          <p>导出任务、日记和对话。API Key 不会被导出。</p>
          <div className="row-actions">
            <button className="button button--dark" onClick={exportData}>
              导出 JSON 备份
            </button>
            <label className="button button--plain file-button">
              导入备份
              <input type="file" accept="application/json" onChange={importData} />
            </label>
          </div>
        </article>
        <article className="privacy-note">
          <strong>你的数据，归你。</strong>
          <p>开启云端同步后，电脑和手机使用同一份数据；清除浏览器数据前仍建议保留 JSON 备份。</p>
        </article>
      </section>
    </main>
  );

  return (
    <div className="app-shell">
      <a className="skip-link" href="#main-content">跳到主要内容</a>
      <aside className="sidebar">
        <button className="brand" onClick={() => setView("today")}>
          <span className="brand-mark"><i /></span>
          <span><strong>西瓜老师</strong><small>个人工作台</small></span>
        </button>
        <nav aria-label="主要导航">
          {navItems.map((item, index) => (
            <button
              className={view === item.id ? "is-active" : ""}
              key={item.id}
              onClick={() => setView(item.id)}
            >
              <span>{pad(index + 1)}</span>
              <strong>{item.label}</strong>
              <small>{item.hint}</small>
            </button>
          ))}
        </nav>
        <div className="sidebar-quote">
          <span>今日提醒</span>
          <p>把复杂的事，放回一小步。</p>
        </div>
      </aside>

      <div className="main-area">
        <header className="mobile-header">
          <button className="brand" onClick={() => setView("today")}>
            <span className="brand-mark"><i /></span>
            <span><strong>西瓜老师</strong><small>个人工作台</small></span>
          </button>
          <button onClick={() => setView("settings")}>设置</button>
        </header>
        {view === "today" && renderToday()}
        {view === "year" && renderYear()}
        {view === "month" && renderMonth()}
        {view === "agenda" && renderAgenda()}
        {view === "brief" && renderBrief()}
        {view === "diary" && renderDiary()}
        {view === "settings" && renderSettings()}
      </div>

      <nav className="mobile-nav" aria-label="手机端导航">
        {navItems.filter((item) => item.id !== "settings").map((item) => (
          <button
            className={view === item.id ? "is-active" : ""}
            key={item.id}
            onClick={() => setView(item.id)}
          >
            {item.label}
          </button>
        ))}
      </nav>

      {taskModal && editingTask && (
        <TaskModal
          task={editingTask}
          apiKey={data.apiKey}
          onClose={() => setTaskModal(false)}
          onNeedApiKey={() => {
            setTaskModal(false);
            setView("settings");
            setNotice("先在设置里填入 DeepSeek API Key，AI 才能帮你安排。");
          }}
          onSave={(task) => {
            updateTask(task);
            setTaskModal(false);
            setNotice(task.start ? "任务已经放进时间线。" : "任务已经收进收件箱。");
          }}
          onDelete={
            data.tasks.some((task) => task.id === editingTask.id)
              ? () => {
                  if (!removeTask(editingTask.id)) return;
                  setTaskModal(false);
                  setEditingTask(null);
                  setNotice("任务已删除。");
                }
              : undefined
          }
        />
      )}

      {notice && (
        <button className="toast" onClick={() => setNotice("")} aria-live="polite">
          {notice}
        </button>
      )}
    </div>
  );
}

function PageHeader({
  eyebrow,
  title,
  actionLabel,
  onAction,
}: {
  eyebrow: string;
  title: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <header className="page-header">
      <div>
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
      </div>
      {actionLabel && onAction && (
        <button className="button button--dark" onClick={onAction}>
          {actionLabel}
        </button>
      )}
    </header>
  );
}

function EmptyState({ text, action }: { text: string; action: () => void }) {
  return (
    <div className="empty-state">
      <span className="empty-watermelon"><i /><i /><i /></span>
      <p>{text}</p>
      <button onClick={action}>现在加一件事</button>
    </div>
  );
}

function TaskModal({
  task,
  apiKey,
  onSave,
  onClose,
  onNeedApiKey,
  onDelete,
}: {
  task: Task;
  apiKey: string;
  onSave: (task: Task) => void;
  onClose: () => void;
  onNeedApiKey: () => void;
  onDelete?: () => void;
}) {
  const [draft, setDraft] = useState(task);
  const [timeError, setTimeError] = useState("");
  const [aiInput, setAiInput] = useState("");
  const [aiMessage, setAiMessage] = useState("");
  const [isAiArranging, setIsAiArranging] = useState(false);

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [onClose]);

  function submit(event: FormEvent) {
    event.preventDefault();
    if (!draft.title.trim()) return;
    if (!draft.start && draft.end) {
      setTimeError("请先填写开始时间，或同时清空开始和结束时间。");
      return;
    }
    if (draft.start && draft.end && draft.end <= draft.start) {
      setTimeError("结束时间需要晚于开始时间。");
      return;
    }
    onSave({ ...draft, date: draft.date || todayKey, title: draft.title.trim() });
  }

  async function applyAiArrangement() {
    const request = aiInput.trim();
    if (!request || isAiArranging) return;
    if (!apiKey) {
      onNeedApiKey();
      return;
    }
    setIsAiArranging(true);
    setAiMessage("");
    try {
      const response = await fetch("https://api.deepseek.com/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          temperature: 0.1,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: `把用户的一句话整理成一个待办任务。今天是 ${todayKey}。
只能使用用户明确提供的信息，不得编造日期、时间、人物或细节。没有明确日期时使用今天 ${todayKey}；没有明确时间时 start 和 end 为空字符串，表示放入收件箱。tag 只能是 工作、生活、重要。
只输出 JSON：{"title":"任务标题","date":"YYYY-MM-DD 或空字符串","start":"HH:mm 或空字符串","end":"HH:mm 或空字符串","tag":"工作|生活|重要","notes":"可选补充说明"}。`,
            },
            { role: "user", content: request },
          ],
        }),
      });
      if (!response.ok) throw new Error("DeepSeek 请求失败");
      const result = (await response.json()) as {
        choices?: { message?: { content?: string } }[];
      };
      const raw = result.choices?.[0]?.message?.content?.trim() || "";
      const parsed = JSON.parse(
        raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""),
      ) as Partial<Task>;
      if (!parsed.title?.trim()) throw new Error("无效任务");
      const tag: TaskTag = ["工作", "生活", "重要"].includes(parsed.tag || "")
        ? parsed.tag as TaskTag
        : "工作";
      setDraft((current) => ({
        ...current,
        title: parsed.title?.trim() || current.title,
        date: /^\d{4}-\d{2}-\d{2}$/.test(parsed.date || "") ? parsed.date || todayKey : todayKey,
        start: /^\d{2}:\d{2}$/.test(parsed.start || "") ? parsed.start || "" : "",
        end: /^\d{2}:\d{2}$/.test(parsed.end || "") ? parsed.end || "" : "",
        tag,
        notes: parsed.notes?.trim() || current.notes,
      }));
      setAiMessage(parsed.start ? "已帮你填好时间，保存前可以再改。" : "没有具体时间，将先放入收件箱。");
    } catch {
      setAiMessage("这次没有整理成功，换一种更具体的说法试试。");
    } finally {
      setIsAiArranging(false);
    }
  }

  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={onClose}>
      <form
        className="task-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="task-modal-title"
        onSubmit={submit}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="modal-heading">
          <div>
            <p className="eyebrow">{task.title ? "调整安排" : "新便签"}</p>
            <h2 id="task-modal-title">{task.title ? "编辑任务" : "安排一件事"}</h2>
          </div>
          <button type="button" onClick={onClose} aria-label="关闭">×</button>
        </div>
        <label className="field">
          <span>任务标题</span>
          <input
            autoFocus
            value={draft.title}
            onChange={(event) => setDraft({ ...draft, title: event.target.value })}
            placeholder="要完成什么？"
            required
          />
        </label>
        <div className="ai-arranger">
          <div>
            <span>不会安排？交给 AI</span>
            <small>例如：下周三下午和张老师确认方案</small>
          </div>
          <textarea
            value={aiInput}
            onChange={(event) => setAiInput(event.target.value)}
            placeholder="用一句话说说你想做的事"
            aria-label="让 AI 帮忙安排任务"
          />
          <button
            type="button"
            className="button button--plain"
            disabled={isAiArranging || !aiInput.trim()}
            onClick={() => void applyAiArrangement()}
          >
            {isAiArranging ? "正在整理…" : "AI 帮我填写"}
          </button>
          {aiMessage && <p className="ai-arranger-message" role="status">{aiMessage}</p>}
        </div>
        <div className="field-grid">
          <label className="field">
            <span>日期</span>
            <input
              type="date"
              value={draft.date || todayKey}
              onChange={(event) => setDraft({ ...draft, date: event.target.value })}
              required
            />
            <small>不填时间＝放入收件箱</small>
          </label>
          <label className="field">
            <span>标签</span>
            <select
              value={draft.tag}
              onChange={(event) =>
                setDraft({ ...draft, tag: event.target.value as TaskTag })
              }
            >
              <option>工作</option>
              <option>生活</option>
              <option>重要</option>
            </select>
          </label>
          <label className="field">
            <span>开始</span>
            <input
              type="time"
              value={draft.start}
              onChange={(event) => {
                setTimeError("");
                setDraft({
                  ...draft,
                  start: event.target.value,
                  end: event.target.value ? draft.end : "",
                });
              }}
            />
          </label>
          <label className="field">
            <span>结束</span>
            <input
              type="time"
              value={draft.end}
              aria-describedby={timeError ? "task-time-error" : undefined}
              onChange={(event) => {
                setTimeError("");
                setDraft({ ...draft, end: event.target.value });
              }}
            />
          </label>
        </div>
        {timeError && <p className="field-error" id="task-time-error" role="alert">{timeError}</p>}
        <label className="field">
          <span>补充说明</span>
          <textarea
            value={draft.notes}
            onChange={(event) => setDraft({ ...draft, notes: event.target.value })}
            placeholder="可选：提醒自己从哪里开始"
          />
        </label>
        <div className="modal-actions">
          {onDelete && (
            <button type="button" className="button button--plain modal-delete" onClick={onDelete}>
              删除任务
            </button>
          )}
          <button type="button" className="button button--plain" onClick={onClose}>
            取消
          </button>
          <button type="submit" className="button button--dark">
            {draft.start ? "放进时间线" : "放入收件箱"}
          </button>
        </div>
      </form>
    </div>
  );
}
