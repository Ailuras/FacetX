import Foundation

/// Lightweight in-app localization. Strings are authored as (English, 中文)
/// pairs and selected by `AppSettings.language` (default English). This keeps
/// the UI consistent instead of mixing languages, while letting the user switch.
enum L10n {
    enum Key {
        // Tabs
        case general, api, automation, papers, rules
        // General
        case storageLocation, currentLocation, change, restoreDefault, storageHint, pdfLocation
        case interface, showInMenuBar, language, menuBarHint
        case changeStorageTitle, migrateDB, switchOnly, cancel, migratePrompt
        case choose, storageUpdated
        // API
        case translationSection, enableTranslation, apiKeyHint, model, targetLanguage, provider
        case testConnection, testingConnection, connectionOK, connectionFailed, connectionUntested
        case refreshModels, loadingModels, modelsLoaded, modelsUnavailable
        case apiConnection, modelSelection, apiKey, baseURL
        // Papers
        case dailyRecommendations, dailyCount, qualitySlots, highScoreThreshold, recentWindow
        case openAlexFetch, contactEmail, perPage, fetchDays, maxResults, topicFilter
        // Automation
        case enableAutomation, monthlyFetch, dailyRecommend
        // Rules
        case interestsTracks, venueRatings
        case noTracks, name, searchQuery, keywordsCSV, addTrack
        case noVenues, abbr, matchPhrase, tier, addVenue, field, newField
        case venueChangesApplied
        case applyChanges, applyChangesHint
        case tierSettings, tierRank, tierPointsValue, addTier
        case citationScoring, citationScoringHint
        case breakpointUpTo, pointsPerCitation, maxCitationPointsLabel
        case addBreakpoint, noBreakpoints, noCap
        case importRules, exportRules, usePreset
        case usePresetTitle, usePresetMessage, confirm
        case importSuccess, importFailed
        case tracksHint, venuesHint, tiersHint
        case deleteRuleTitle, deleteRuleMessage
        // Settings file
        case path, open, revealInFinder, settingsFile, settingsFileHint
        // Menu bar
        case noRecommendations, runRecommendEngine, todaysTopPicks
        case openPDF, markRead, markStarred, markSkip, cancelRecommendation, openInVellumX, openVellumX, quit
        // PDF fetch / reveal
        case fetchPDF, showPdfInFinder, resolvingPDF, pdfDownloaded, pdfNotAvailable, pdfNotFound, paperNotFound
        case setPdfFromFile, removePdf, choosePdf, pdfSet, pdfRemoved, notAPdfFile, pdfSetFailed
        // Citation export
        case cite, copiedBibtex
        case copyBibtex, copyApa, copyMarkdown, copyRis, copyPlain
        case copiedApa, copiedMarkdown, copiedRis, copiedPlain
        case copyTitle, copyDoi, copyAuthors
        case copiedTitle, copiedDoi, copiedAuthors
        // Related papers
        case relatedPapers, similarPapers, citedBy, addToLibrary, addedToLibrary
        case loadingRelated, noRelated
        // Menu commands (keyboard shortcuts)
        case menuView, menuPaper
        case cmdAllPapers, cmdRecommended, cmdPending, cmdStarred, cmdRead, cmdSkipped
        case cmdPrevPaper, cmdNextPaper
        case cmdFetch, cmdRecommend
        case cmdMarkPending, cmdMarkStarred, cmdMarkRead, cmdMarkSkip
        case cmdAddTag
        case cmdCopyBibtex, cmdOpenLink, cmdClearFilters
        case clearFiltersToast
        case cmdExportBib
        case exportBibSuccess, exportBibFailed, exportBibEmpty
        case cmdSurprise, surpriseEmpty
        case cmdTranslateAbstract
        case fetchConfirmTitle, fetchConfirmMessage
        case cmdDeletePaper, delete, deleteConfirmTitle, deleteConfirmMessage
        case cmdUpdatePaper
        case cmdSetStatus, cmdAddToCollection, batchSelected
    }

    @MainActor
    static func t(_ key: Key) -> String {
        AppSettings.shared.language == "zh" ? pair(key).1 : pair(key).0
    }

    /// For strings that need runtime interpolation (numbers, names) and so can't
    /// be a static `Key`. Picks the language the same way `t` does.
    @MainActor
    static func pick(_ en: String, _ zh: String) -> String {
        AppSettings.shared.language == "zh" ? zh : en
    }

    private static func pair(_ key: Key) -> (String, String) {
        switch key {
        case .general:            return ("General", "通用")
        case .api:                return ("API", "API")
        case .automation:         return ("Automation", "自动化")
        case .papers:             return ("Papers", "论文")
        case .rules:              return ("Rules", "学术规则")

        case .storageLocation:    return ("Storage Location", "存储位置")
        case .currentLocation:    return ("Database", "数据库")
        case .pdfLocation:        return ("Downloaded PDFs", "已下载 PDF")
        case .change:             return ("Change…", "更改…")
        case .restoreDefault:     return ("Restore Default", "恢复默认")
        case .storageHint:        return ("Folder holding vellumx.db and downloaded PDFs. Defaults to Application Support; pick another folder to relocate them together.",
                                          "存放 vellumx.db 与已下载 PDF 的文件夹。默认位于 Application Support，可另选文件夹一并迁移。")
        case .interface:          return ("Interface", "界面")
        case .showInMenuBar:      return ("Show in Menu Bar", "在菜单栏显示")
        case .language:           return ("Language", "语言")
        case .menuBarHint:        return ("Hiding it only removes the status-bar icon; the main window is unaffected.",
                                          "关闭后仅隐藏右上角状态栏图标，主窗口不受影响。")
        case .changeStorageTitle: return ("Change Storage Location", "更改存储位置")
        case .migrateDB:          return ("Migrate existing database", "迁移现有数据库")
        case .switchOnly:         return ("Switch only, don't migrate", "仅切换，不迁移")
        case .cancel:             return ("Cancel", "取消")
        case .migratePrompt:      return ("Move the current database to the new location? If a vellumx.db already exists there, it will be replaced.",
                                          "是否把当前数据库迁移到新位置？\n如目标位置已存在 vellumx.db，迁移会直接替换它。")
        case .choose:             return ("Choose", "选择")
        case .storageUpdated:     return ("Storage location updated:", "已更新存储位置：")

        case .translationSection: return ("Translation", "翻译")
        case .enableTranslation:  return ("Enable abstract translation", "启用摘要翻译")
        case .apiKeyHint:         return ("The API key is saved in this app variant's settings.json.",
                                          "API Key 保存在当前 app 变体的 settings.json 中。")
        case .model:              return ("Model", "模型")
        case .targetLanguage:     return ("Target language", "目标语言")
        case .provider:           return ("Provider", "提供商")
        case .testConnection:     return ("Test Connection", "测试连接")
        case .testingConnection:  return ("Testing connection…", "正在测试连接…")
        case .connectionOK:       return ("Connection OK", "连接正常")
        case .connectionFailed:   return ("Connection failed", "连接失败")
        case .connectionUntested: return ("Untested", "未测试")
        case .refreshModels:      return ("Refresh Models", "刷新模型")
        case .loadingModels:      return ("Loading models…", "正在加载模型…")
        case .modelsLoaded:       return ("Models loaded", "模型已加载")
        case .modelsUnavailable:  return ("Configure API key, then refresh models.", "配置 API Key 后刷新模型。")
        case .apiConnection:      return ("Connection", "连接")
        case .modelSelection:     return ("Model Selection", "模型选择")
        case .apiKey:             return ("API Key", "API Key")
        case .baseURL:            return ("Base URL", "Base URL")

        case .dailyRecommendations: return ("Daily Recommendations", "每日推荐")
        case .dailyCount:         return ("Daily count", "每日推荐数")
        case .qualitySlots:       return ("Quality-priority slots", "质量优先槽位")
        case .highScoreThreshold: return ("High-score threshold", "高分阈值")
        case .recentWindow:       return ("Recent window (days)", "新近窗口（天）")
        case .openAlexFetch:      return ("OpenAlex Fetch", "OpenAlex 抓取")
        case .contactEmail:       return ("Contact email", "联系邮箱")
        case .perPage:            return ("Per page", "每页条数")
        case .fetchDays:          return ("Fetch days", "抓取天数")
        case .maxResults:         return ("Max results", "最大结果数")
        case .topicFilter:        return ("Topic filter", "主题过滤")
        case .enableAutomation:   return ("Enable automation", "启用自动化")
        case .monthlyFetch:       return ("Fetch monthly", "每月抓取")
        case .dailyRecommend:     return ("Recommend daily", "每日推荐")
        case .interestsTracks:    return ("Interests (Tracks)", "研究方向 (Tracks)")
        case .venueRatings:       return ("Venue Ratings", "会议评级")
        case .noTracks:           return ("No tracks yet. Add one below.", "暂无方向。点击下方按钮添加。")
        case .name:               return ("Name", "名称")
        case .searchQuery:        return ("Search query", "搜索词 (query)")
        case .keywordsCSV:        return ("Keywords (comma-separated)", "关键词（逗号分隔）")
        case .addTrack:           return ("Add Track", "添加方向")
        case .noVenues:           return ("No venues yet. Add one below.", "暂无会议。点击下方按钮添加。")
        case .abbr:               return ("Abbr.", "缩写")
        case .matchPhrase:        return ("Match phrase", "匹配词")
        case .tier:               return ("Tier", "评级")
        case .addVenue:           return ("Add Venue", "添加会议")
        case .field:              return ("Field", "领域")
        case .newField:           return ("New Field…", "新建领域…")
        case .venueChangesApplied:return ("Updated paper metadata:", "已更新论文元数据：")
        case .applyChanges:       return ("Recompute Library", "重算全库")
        case .applyChangesHint:   return ("Recompute cached venue, tier, and score across the whole library to reflect your edited rules.",
                                          "重新计算整个论文库缓存的会议、评级和分数，使其反映你修改后的规则。")

        case .tierSettings:       return ("Tier Settings", "等级设置")
        case .tierRank:           return ("Rank", "等级")
        case .tierPointsValue:    return ("Points", "积分")
        case .addTier:            return ("Add Tier", "添加等级")
        case .citationScoring:    return ("Citation Scoring", "引用评分")
        case .citationScoringHint:return ("Configure how citations contribute to paper scores. Leave empty to disable citation scoring.",
                                          "配置引用数如何影响论文分数。留空则不启用引用评分。")
        case .breakpointUpTo:     return ("Up to", "上限")
        case .pointsPerCitation:  return ("Pts/cite", "分/引用")
        case .maxCitationPointsLabel: return ("Max citation points", "引用得分上限")
        case .addBreakpoint:      return ("Add Segment", "添加区间")
        case .noBreakpoints:      return ("Citation scoring disabled. Add a segment to enable.", "引用评分未启用。添加区间以启用。")
        case .noCap:              return ("No cap", "不封顶")
        case .importRules:        return ("Import…", "导入…")
        case .exportRules:        return ("Export…", "导出…")
        case .usePreset:          return ("Use Preset", "使用预设")
        case .usePresetTitle:     return ("Reset to Preset?", "恢复预设配置？")
        case .usePresetMessage:   return ("This will replace all current rules (tracks, venues, tiers, scoring) with the built-in defaults. This cannot be undone.",
                                          "此操作将用内置默认值替换当前的所有规则（研究方向、会议评级、等级、评分）。此操作不可撤销。")
        case .confirm:            return ("Confirm", "确认")
        case .importSuccess:      return ("Rules imported successfully.", "规则导入成功。")
        case .importFailed:       return ("Import failed:", "导入失败：")
        case .tracksHint:         return ("Search queries and keywords that decide what gets fetched and recommended.",
                                          "决定抓取与推荐内容的搜索词和关键词。")
        case .venuesHint:         return ("Match venue name patterns to a research field and quality tier.",
                                          "将会议名称匹配规则映射到研究领域与质量评级。")
        case .tiersHint:          return ("Points awarded to each quality tier when scoring a paper.",
                                          "为论文评分时，各质量评级所得的分值。")
        case .deleteRuleTitle:    return ("Delete this entry?", "删除此条目？")
        case .deleteRuleMessage:  return ("This removes it from your academic rules.", "将把它从学术规则中移除。")

        case .path:               return ("Path", "路径")
        case .open:               return ("Open", "打开")
        case .revealInFinder:     return ("Reveal in Finder", "在访达中显示")
        case .settingsFile:       return ("Settings File", "设置文件")
        case .settingsFileHint:   return ("All preferences are stored in this JSON file. It is generated on first launch and can be edited by hand; relaunch VellumX to apply changes.",
                                          "所有偏好设置都存储在这个 JSON 文件里。它在首次启动时生成，可手动编辑；改完后重启 VellumX 生效。")

        case .noRecommendations:  return ("No recommendations for today.", "今天还没有推荐。")
        case .runRecommendEngine: return ("Run Recommend Engine", "运行推荐引擎")
        case .todaysTopPicks:     return ("Today's Top Picks:", "今日精选：")
        case .openPDF:            return ("Open PDF", "打开 PDF")
        case .fetchPDF:           return ("Fetch PDF", "获取 PDF")
        case .showPdfInFinder:    return ("Show PDF in Finder", "在访达中显示 PDF")
        case .resolvingPDF:       return ("Resolving open-access PDF…", "正在解析开放获取 PDF…")
        case .paperNotFound:      return ("Paper not found", "未找到论文")
        case .pdfDownloaded:      return ("PDF downloaded", "PDF 已下载")
        case .pdfNotAvailable:    return ("No downloadable PDF found", "未找到可下载的 PDF")
        case .pdfNotFound:        return ("No open-access PDF found", "无开放获取 PDF")
        case .setPdfFromFile:     return ("Set PDF from File…", "从文件设置 PDF…")
        case .removePdf:          return ("Remove PDF", "移除 PDF")
        case .choosePdf:          return ("Choose", "选择")
        case .pdfSet:             return ("PDF set", "PDF 已设置")
        case .pdfRemoved:         return ("PDF removed", "PDF 已移除")
        case .notAPdfFile:        return ("The selected file is not a PDF", "所选文件不是 PDF")
        case .pdfSetFailed:       return ("Could not set the PDF", "无法设置 PDF")
        case .markRead:           return ("Mark Read", "标记已读")
        case .markStarred:        return ("Mark Starred", "标记收藏")
        case .markSkip:           return ("Skip", "跳过")
        case .cancelRecommendation:return ("Cancel Recommendation", "取消推荐")
        case .openInVellumX:      return ("Open in VellumX", "在 VellumX 中打开")
        case .openVellumX:        return ("Open VellumX", "打开 VellumX")
        case .quit:               return ("Quit", "退出")

        case .cite:               return ("Copy Citation", "复制引用")
        case .copiedBibtex:       return ("BibTeX copied to clipboard", "BibTeX 已复制到剪贴板")
        case .copyBibtex:         return ("Copy BibTeX", "复制 BibTeX")
        case .copyApa:            return ("Copy APA", "复制 APA")
        case .copyMarkdown:       return ("Copy Markdown", "复制 Markdown")
        case .copyRis:            return ("Copy RIS", "复制 RIS")
        case .copyPlain:          return ("Copy Plain Text", "复制纯文本")
        case .copiedPlain:        return ("Plain citation copied", "纯文本引用已复制")
        case .copyTitle:          return ("Copy Title", "复制标题")
        case .copyDoi:            return ("Copy DOI", "复制 DOI")
        case .copyAuthors:        return ("Copy Authors", "复制作者")
        case .copiedTitle:        return ("Title copied", "标题已复制")
        case .copiedDoi:          return ("DOI copied", "DOI 已复制")
        case .copiedAuthors:      return ("Authors copied", "作者已复制")
        case .copiedApa:          return ("APA citation copied", "APA 引用已复制")
        case .copiedMarkdown:     return ("Markdown citation copied", "Markdown 引用已复制")
        case .copiedRis:          return ("RIS citation copied", "RIS 引用已复制")

        case .relatedPapers:      return ("Related Papers", "相关论文")
        case .similarPapers:      return ("Similar", "相似")
        case .citedBy:            return ("Cited by", "被引用")
        case .addToLibrary:       return ("Add to library", "加入库")
        case .addedToLibrary:     return ("In library", "已在库")
        case .loadingRelated:     return ("Loading related papers…", "正在加载相关论文…")
        case .noRelated:          return ("No related papers found.", "未找到相关论文。")

        case .menuView:           return ("View", "视图")
        case .menuPaper:          return ("Paper", "论文")
        case .cmdAllPapers:       return ("All Papers", "全部论文")
        case .cmdRecommended:     return ("Recommended", "推荐")
        case .cmdPending:         return ("Pending", "待读")
        case .cmdStarred:         return ("Starred", "已标星")
        case .cmdRead:            return ("Read", "已读")
        case .cmdSkipped:         return ("Skipped", "已跳过")
        case .cmdPrevPaper:       return ("Previous Paper", "上一篇")
        case .cmdNextPaper:       return ("Next Paper", "下一篇")
        case .cmdFetch:           return ("Fetch New Papers", "获取新论文")
        case .cmdRecommend:       return ("Generate Recommendations", "生成推荐")
        case .cmdMarkPending:     return ("Mark as Pending", "标记为待读")
        case .cmdMarkStarred:     return ("Mark as Starred", "标记为已标星")
        case .cmdMarkRead:        return ("Mark as Read", "标记为已读")
        case .cmdMarkSkip:        return ("Mark as Skipped", "标记为已跳过")
        case .cmdAddTag:          return ("Add Tag…", "添加标签…")
        case .cmdCopyBibtex:      return ("Copy BibTeX", "复制 BibTeX")
        case .cmdOpenLink:        return ("Open Link", "打开链接")
        case .cmdClearFilters:    return ("Clear All Filters", "清除所有过滤器")
        case .clearFiltersToast:  return ("Filters cleared", "已清除过滤器")
        case .cmdExportBib:       return ("Export Bibliography…", "导出参考文献…")
        case .exportBibSuccess:   return ("Bibliography exported", "参考文献已导出")
        case .exportBibFailed:    return ("Bibliography export failed", "参考文献导出失败")
        case .exportBibEmpty:     return ("No papers in the current view to export.", "当前视图没有可导出的论文。")
        case .cmdSurprise:        return ("Surprise Me", "随机一篇")
        case .surpriseEmpty:      return ("No pending papers to pick from.", "没有可挑选的待读论文。")
        case .cmdTranslateAbstract: return ("Translate Abstract", "翻译摘要")
        case .fetchConfirmTitle:  return ("Fetch New Papers?", "获取新论文？")
        case .fetchConfirmMessage:
            return ("This contacts OpenAlex and may take a while.",
                    "这会联网请求 OpenAlex，可能需要一些时间。")
        case .cmdSetStatus:       return ("Set Status", "设置状态")
        case .cmdAddToCollection: return ("Add to Collection", "加入 Collection")
        case .batchSelected:      return ("papers selected", "篇已选")
        case .cmdUpdatePaper:     return ("Update from OpenAlex", "从 OpenAlex 更新")
        case .cmdDeletePaper:     return ("Delete Paper", "删除论文")
        case .delete:             return ("Delete", "删除")
        case .deleteConfirmTitle: return ("Delete this paper?", "删除这篇论文？")
        case .deleteConfirmMessage:
            return ("This permanently removes the paper and its notes, tags, and collection links.",
                    "将永久删除该论文及其笔记、标签与 collection 关联。")
        }
    }
}
