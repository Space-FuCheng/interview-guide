// F01：在这里定义报告显示类型和报告状态类型。
export interface ResumeAnalysisResponse {
    totalScore: number;
    summary: string;
    advantages: string[];
    suggestions: ResumeAnalysisSuggestion[];
}

export type AnalysisPageState =
    'LOADING' | 'SUCCESS' | 'FAIL';

export interface ResumeAnalysisSuggestion {
    type: string;
    priority: '高' | '中' | '低';
    problem: string;
    suggestionDetail: string;
}
