import ResumeReport from '../components/ResumeReport'
import {AnalysisPageState, ResumeAnalysisResponse} from "../types/resumeReport.ts";
import {useState} from "react";


export default function ResumeReportPractice() {
    const report: ResumeAnalysisResponse = {
        totalScore: 10,
        summary: "整体不错",
        advantages : [
            'java1', 'java2'
        ],
        suggestions: [
            {
                type:'type1',
                priority:'高',
                problem:'还行',
                suggestionDetail:'没有具体建议'
            }
        ]
    };
    const [pageState, setPageState] = useState<AnalysisPageState>('LOADING');



  return <main>F01 简历报告练习
      {pageState === 'SUCCESS' && <ResumeReport report={report}></ResumeReport> }
      {pageState === 'LOADING' && <p>加载中...</p>}
      {pageState === 'FAIL' && <p>加载失败</p>}
      <button onClick={() => setPageState('SUCCESS')}>点我成功</button><br/>
      <button onClick={() => setPageState('FAIL')}>点我失败</button><br/>
      <button onClick={() => setPageState('LOADING')}>点我加载</button>

  </main>;
}
