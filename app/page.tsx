"use client";

import { ChangeEvent, FormEvent, useEffect, useMemo, useState } from "react";

type View =
  | "today"
  | "year"
  | "month"
  | "agenda"
  | "diary"
  | "ai"
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

type AppData = {
  tasks: Task[];
  diaries: Diary[];
  messages: ChatMessage[];
  diaryMessages: ChatMessage[];
  apiKey: string;
};

const STORAGE_KEY = "xigua-personal-desk-v1";

const pad = (value: number) => String(value).padStart(2, "0");
const toDateKey = (date: Date) =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const todayKey = toDateKey(new Date());
const uid = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;

const seedData: AppData = {
  tasks: [
    {
      id: "seed-1",
      title: "整理本周最重要的三个交付",
      date: todayKey,
      start: "09:30",
      end: "10:30",
      tag: "重要",
      notes: "先列结果，再拆动作。",
      done: false,
    },
    {
      id: "seed-2",
      title: "回复需要推进的消息",
      date: todayKey,
      start: "11:00",
      end: "11:30",
      tag: "工作",
      notes: "",
      done: true,
    },
    {
      id: "seed-3",
      title: "散步二十分钟",
      date: todayKey,
      start: "18:30",
      end: "18:50",
      tag: "生活",
      notes: "不带耳机。",
      done: false,
    },
  ],
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
      content: "今天，想从哪里说起？可以从一个刚刚发生的瞬间开始。",
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
      tasks: Array.isArray(parsed.tasks) ? parsed.tasks : seedData.tasks,
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
  { id: "diary", label: "日记", hint: "回声" },
  { id: "ai", label: "AI 助手", hint: "整理" },
  { id: "settings", label: "设置", hint: "本地" },
];

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

function Character({ compact = false }: { compact?: boolean }) {
  return (
    <div className={`character ${compact ? "character--compact" : ""}`}>
      <img
        src="/assets/xigua-teacher-cutout.png"
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
    updatedAt: Date.now(),
  });
  const [diarySearch, setDiarySearch] = useState("");
  const [diaryInput, setDiaryInput] = useState("");
  const [diaryView, setDiaryView] = useState<"chat" | "draft">("chat");
  const [diaryLength, setDiaryLength] = useState<"简洁" | "长文">("简洁");
  const [isDiaryThinking, setIsDiaryThinking] = useState(false);
  const [chatInput, setChatInput] = useState("");
  const [isThinking, setIsThinking] = useState(false);
  const [notice, setNotice] = useState("");

  useEffect(() => {
    setData(safeLoad());
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }, [data, hydrated]);

  const selectedTasks = useMemo(
    () =>
      data.tasks
        .filter((task) => task.date === selectedDate)
        .sort((a, b) => (a.start || "99:99").localeCompare(b.start || "99:99")),
    [data.tasks, selectedDate],
  );
  const todayTasks = useMemo(
    () =>
      data.tasks
        .filter((task) => task.date === todayKey)
        .sort((a, b) => (a.start || "99:99").localeCompare(b.start || "99:99")),
    [data.tasks],
  );
  const completedToday = todayTasks.filter((task) => task.done).length;
  const progress = todayTasks.length
    ? Math.round((completedToday / todayTasks.length) * 100)
    : 0;
  const filteredDiaries = data.diaries
    .filter((diary) =>
      `${diary.title}${diary.body}`.toLowerCase().includes(diarySearch.toLowerCase()),
    )
    .sort((a, b) => b.updatedAt - a.updatedAt);

  function updateTask(task: Task) {
    setData((current) => ({
      ...current,
      tasks: current.tasks.some((item) => item.id === task.id)
        ? current.tasks.map((item) => (item.id === task.id ? task : item))
        : [...current.tasks, task],
    }));
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
    if (!window.confirm("确定删除这项任务吗？")) return;
    setData((current) => ({
      ...current,
      tasks: current.tasks.filter((task) => task.id !== id),
    }));
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
        updatedAt: Date.now(),
      });
    }
  }

  async function sendMessage() {
    const value = chatInput.trim();
    if (!value || isThinking) return;
    if (!data.apiKey) {
      setView("settings");
      setNotice("先在设置里填入 DeepSeek API Key。");
      return;
    }
    const userMessage: ChatMessage = { id: uid(), role: "user", content: value };
    const nextMessages = [...data.messages, userMessage];
    setData((current) => ({ ...current, messages: nextMessages }));
    setChatInput("");
    setIsThinking(true);
    try {
      const context = {
        tasks: data.tasks.filter((task) => task.date >= todayKey).slice(0, 12),
        recentDiaries: data.diaries.slice(0, 3).map(({ date, title, body }) => ({
          date,
          title,
          body,
        })),
      };
      const response = await fetch("https://api.deepseek.com/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${data.apiKey}`,
        },
        body: JSON.stringify({
          model: "deepseek-chat",
          temperature: 0.5,
          messages: [
            {
              role: "system",
              content:
                "你是西瓜老师，一位克制、温和、具体的个人工作助手。每次回答尽量简短，一次只推进一个问题。可以整理任务、澄清优先级或把用户说过的内容整理成日记草稿。只能使用用户消息和提供的本地上下文中明确出现或可直接推断的信息，不得编造人物、地点、情节、时间、因果或心理活动。信息不足时宁可写短。不要鸡汤化，不要过度夸奖。",
            },
            {
              role: "system",
              content: `当前本地上下文：${JSON.stringify(context)}`,
            },
            ...nextMessages.slice(-12).map(({ role, content }) => ({ role, content })),
          ],
        }),
      });
      if (!response.ok) throw new Error("DeepSeek 请求失败");
      const result = (await response.json()) as {
        choices?: { message?: { content?: string } }[];
      };
      const content =
        result.choices?.[0]?.message?.content?.trim() ||
        "这次没有得到有效回复，可以换个说法再试一次。";
      setData((current) => ({
        ...current,
        messages: [
          ...current.messages,
          { id: uid(), role: "assistant", content },
        ],
      }));
    } catch {
      setNotice("没有连接上 DeepSeek，请检查 API Key 或网络后再试。");
    } finally {
      setIsThinking(false);
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
                "你是西瓜老师，也是一位克制、温和的日记陪伴者。基于用户刚刚说过的内容，每次只问一个具体、有用的问题，帮助用户回到当时的瞬间、感受、意义或下一步。回复要短，不做诊断，不连续夸奖，不重复用户大段原话。只能使用用户对话中明确出现或可直接推断的信息，不得编造人物、地点、情节、时间、因果或心理活动。",
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
        "这件事里，最让你记住的是哪个瞬间？";
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

  function useLastReplyAsDraft() {
    const reply = [...data.messages]
      .reverse()
      .find((message) => message.role === "assistant");
    if (!reply) return;
    setDiaryDraft({
      id: "",
      date: selectedDate,
      title: "今天想记下的事",
      body: reply.content,
      mood: "平静",
      updatedAt: Date.now(),
    });
    setView("diary");
    setDiaryView("draft");
    setNotice("已放入日记草稿，请确认修改后再保存。");
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
          tasks: parsed.tasks || [],
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
    <main className="content" id="main-content">
      <section className="today-hero">
        <div className="hero-copy">
          <p className="eyebrow">{formatLongDate(todayKey)}</p>
          <h1>今天，先把重要的事放在眼前。</h1>
          <p className="hero-lead">
            不用把一天塞满。完成一件真正重要的事，也算走了很远。
          </p>
          <div className="hero-actions">
            <button className="button button--dark" onClick={() => openNewTask(todayKey)}>
              添加今天的任务
            </button>
            <button className="button button--plain" onClick={() => setView("diary")}>
              写几句话
            </button>
          </div>
        </div>
        <div className="mentor-panel">
          <div className="mentor-note">
            <span>西瓜老师的小提醒</span>
            <strong>
              {todayTasks.length
                ? `今天有 ${todayTasks.length} 件事，先看最重要的那一件。`
                : "今天还没有安排，先给自己留一个锚点。"}
            </strong>
          </div>
          <Character />
        </div>
      </section>

      <section className="today-grid">
        <article className="paper-card task-card">
          <div className="section-heading">
            <div>
              <p className="eyebrow">今日清单</p>
              <h2>{completedToday} / {todayTasks.length} 已完成</h2>
            </div>
            <div className="progress-stamp">{progress}%</div>
          </div>
          <div className="progress-track">
            <span style={{ width: `${progress}%` }} />
          </div>
          <div className="task-list">
            {todayTasks.length ? (
              todayTasks.map((task) => (
                <div className={`task-row ${task.done ? "is-done" : ""}`} key={task.id}>
                  <button
                    className="check"
                    aria-label={`${task.done ? "取消完成" : "完成"}：${task.title}`}
                    onClick={() => toggleTask(task.id)}
                  >
                    {task.done ? "✓" : ""}
                  </button>
                  <div className="task-main">
                    <strong>{task.title}</strong>
                    <span>{task.start || "全天"} {task.notes ? `· ${task.notes}` : ""}</span>
                  </div>
                  <span className={`tag tag--${task.tag}`}>{task.tag}</span>
                </div>
              ))
            ) : (
              <EmptyState text="今天还是一张空白便签。" action={() => openNewTask(todayKey)} />
            )}
          </div>
        </article>

        <article className="paper-card echo-card">
          <p className="eyebrow">今日回声</p>
          <h2>给今天留一句话</h2>
          <p>不需要完整，不需要深刻。先写下此刻最想记住的一个瞬间。</p>
          <button className="text-link" onClick={() => setView("diary")}>
            打开日记纸张 →
          </button>
          <div className="scribble">每一天，都值得被认真听见。</div>
        </article>
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
            const monthTaskCount = data.tasks.filter((task) =>
              task.date.startsWith(`${year}-${pad(monthIndex + 1)}`),
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
                  <span>{monthTaskCount ? `${monthTaskCount} 项任务` : "留白"}</span>
                </button>
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
                      (task) => task.date === dateKey,
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
      <main className="content" id="main-content">
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
              const dayTasks = data.tasks.filter((task) => task.date === dateKey);
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
                    {dayTasks.slice(0, 3).map((task) => (
                      <span className={`mini-task ${task.done ? "is-done" : ""}`} key={task.id}>
                        {task.title}
                      </span>
                    ))}
                    {dayTasks.length > 3 && <small>还有 {dayTasks.length - 3} 项</small>}
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
      </div>
      <section className="agenda-layout">
        <div className="timeline">
          {selectedTasks.length ? (
            selectedTasks.map((task) => (
              <article className={`timeline-item ${task.done ? "is-done" : ""}`} key={task.id}>
                <div className="time-column">
                  <strong>{task.start || "全天"}</strong>
                  <span>{task.end || ""}</span>
                </div>
                <div className="time-pin" />
                <div className="agenda-task">
                  <span className={`tag tag--${task.tag}`}>{task.tag}</span>
                  <h3>{task.title}</h3>
                  {task.notes && <p>{task.notes}</p>}
                  <div className="row-actions">
                    <button onClick={() => toggleTask(task.id)}>
                      {task.done ? "恢复任务" : "标为完成"}
                    </button>
                    <button
                      onClick={() => {
                        setEditingTask(task);
                        setTaskModal(true);
                      }}
                    >
                      编辑
                    </button>
                    <button className="danger" onClick={() => removeTask(task.id)}>
                      删除
                    </button>
                  </div>
                </div>
              </article>
            ))
          ) : (
            <EmptyState text="这一天还没有安排。" action={() => openNewTask(selectedDate)} />
          )}
        </div>
        <aside className="mentor-aside">
          <Character compact />
          <div>
            <span>西瓜老师</span>
            <p>如果一天只能推进一件事，你希望晚上回头看见哪一件已经完成？</p>
          </div>
        </aside>
      </section>
    </main>
  );

  function shiftDate(amount: number) {
    const date = new Date(`${selectedDate}T12:00:00`);
    date.setDate(date.getDate() + amount);
    setSelectedDate(toDateKey(date));
  }

  const renderDiary = () => (
    <main className="content" id="main-content">
      <PageHeader
        eyebrow="对话型日记"
        title={diaryView === "chat" ? "今天，想从哪里说起？" : "日记草稿"}
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
            <div className="diary-chat-mentor">
              <Character compact />
              <div>
                <strong>西瓜老师在这里听你说。</strong>
                <p>一次只聊一个具体的瞬间。你准备好后，再主动生成日记。</p>
              </div>
            </div>
            <div className="message-list diary-message-list" aria-live="polite">
              {data.diaryMessages.map((message) => (
                <div className={`message message--${message.role}`} key={message.id}>
                  <span>{message.role === "assistant" ? "西瓜老师" : "我"}</span>
                  <p>{message.content}</p>
                </div>
              ))}
              {isDiaryThinking && (
                <div className="thinking">西瓜老师正在认真听……</div>
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
                placeholder="现在，有什么想聊的吗？"
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

  const renderAI = () => (
    <main className="content content--narrow" id="main-content">
      <PageHeader eyebrow="只在你邀请时出现" title="和西瓜老师聊一聊" />
      <section className="chat-shell">
        <div className="chat-intro">
          <Character compact />
          <div>
            <strong>我可以帮你梳理今天的任务，或把你说过的话整理成日记草稿。</strong>
            <p>我不会自动保存，也不会补写你没有说过的经历。</p>
          </div>
        </div>
        <div className="message-list" aria-live="polite">
          {data.messages.map((message) => (
            <div className={`message message--${message.role}`} key={message.id}>
              <span>{message.role === "assistant" ? "西瓜老师" : "我"}</span>
              <p>{message.content}</p>
            </div>
          ))}
          {isThinking && <div className="thinking">西瓜老师正在整理……</div>}
        </div>
        <div className="chat-tools">
          <button onClick={useLastReplyAsDraft}>把最后回复放入日记草稿</button>
          <button
            className="danger"
            onClick={() => {
              if (!window.confirm("确定清空这段对话吗？")) return;
              setData((current) => ({
                ...current,
                messages: seedData.messages,
              }));
            }}
          >
            清空对话
          </button>
        </div>
        <div className="chat-composer">
          <textarea
            value={chatInput}
            onChange={(event) => setChatInput(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter" && !event.shiftKey) {
                event.preventDefault();
                void sendMessage();
              }
            }}
            placeholder="例如：帮我判断今天三件事的优先级"
            aria-label="给西瓜老师的消息"
          />
          <button
            className="button button--dark"
            disabled={isThinking || !chatInput.trim()}
            onClick={() => void sendMessage()}
          >
            发送
          </button>
        </div>
      </section>
    </main>
  );

  const renderSettings = () => (
    <main className="content content--narrow" id="main-content">
      <PageHeader eyebrow="安静地配置一次" title="设置" />
      <section className="settings-stack">
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
          <p>任务和日记默认只在这台设备的这个浏览器里。清除浏览器数据前，记得先导出备份。</p>
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
        {view === "diary" && renderDiary()}
        {view === "ai" && renderAI()}
        {view === "settings" && renderSettings()}
      </div>

      <nav className="mobile-nav" aria-label="手机端导航">
        {navItems.slice(0, 6).map((item) => (
          <button
            className={view === item.id ? "is-active" : ""}
            key={item.id}
            onClick={() => setView(item.id)}
          >
            {item.label.replace("AI 助手", "AI")}
          </button>
        ))}
      </nav>

      {taskModal && editingTask && (
        <TaskModal
          task={editingTask}
          onClose={() => setTaskModal(false)}
          onSave={(task) => {
            updateTask(task);
            setTaskModal(false);
            setNotice("任务已经放进日历。");
          }}
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
  onSave,
  onClose,
}: {
  task: Task;
  onSave: (task: Task) => void;
  onClose: () => void;
}) {
  const [draft, setDraft] = useState(task);

  function submit(event: FormEvent) {
    event.preventDefault();
    if (!draft.title.trim()) return;
    onSave({ ...draft, title: draft.title.trim() });
  }

  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={onClose}>
      <form
        className="task-modal"
        onSubmit={submit}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="modal-heading">
          <div>
            <p className="eyebrow">新便签</p>
            <h2>{task.title ? "编辑任务" : "安排一件事"}</h2>
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
        <div className="field-grid">
          <label className="field">
            <span>日期</span>
            <input
              type="date"
              value={draft.date}
              onChange={(event) => setDraft({ ...draft, date: event.target.value })}
              required
            />
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
              onChange={(event) => setDraft({ ...draft, start: event.target.value })}
            />
          </label>
          <label className="field">
            <span>结束</span>
            <input
              type="time"
              value={draft.end}
              onChange={(event) => setDraft({ ...draft, end: event.target.value })}
            />
          </label>
        </div>
        <label className="field">
          <span>补充说明</span>
          <textarea
            value={draft.notes}
            onChange={(event) => setDraft({ ...draft, notes: event.target.value })}
            placeholder="可选：提醒自己从哪里开始"
          />
        </label>
        <div className="modal-actions">
          <button type="button" className="button button--plain" onClick={onClose}>
            取消
          </button>
          <button type="submit" className="button button--dark">
            放进日历
          </button>
        </div>
      </form>
    </div>
  );
}
