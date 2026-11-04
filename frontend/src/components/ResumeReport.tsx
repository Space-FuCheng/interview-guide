// F01：在这里实现接收报告数据的展示组件。


import type {ResumeAnalysisResponse} from "../types/resumeReport.ts";

interface ResumeProps {
    report:ResumeAnalysisResponse;
}

export default function ResumeReport({report}:ResumeProps) {

    return <div>简历报告
        <div>
            {/*{Object.entries(report).map(([key, value]) => {*/}
            {/*    return <div key={key}>*/}
            {/*        <strong>{key}</strong>*/}
            {/*        <span>{JSON.stringify(value)}</span>*/}
            {/*    </div>*/}
            {/*})}*/}
            总分: {report.totalScore}<br/>
            总结:{report.summary}<br/>
            优势:{report.advantages.map((i) => {
                return <div key={i}>{i}</div>
        })}<br/>

        </div>
    </div>

}