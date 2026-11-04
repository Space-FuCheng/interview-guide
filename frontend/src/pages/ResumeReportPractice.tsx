import ResumeReport from '../components/ResumeReport'
import {AnalysisPageState, ResumeAnalysisResponse} from "../types/resumeReport.ts";
import {ChangeEvent, useState} from "react";
import {RESUME_FILE_POLICY, validateUploadFile} from "../utils/batchUpload.ts";


export default function ResumeReportPractice() {
    const report: ResumeAnalysisResponse = {
        totalScore: 10,
        summary: "整体不错",
        advantages: [
            'java1', 'java2'
        ],
        suggestions: [
            {
                type: 'type1',
                priority: '高',
                problem: '还行',
                suggestionDetail: '没有具体建议'
            }
        ]
    };
    const [pageState, setPageState] = useState<AnalysisPageState>('LOADING');


    const [file, setFile] = useState<File | null>(null);
    const [uploadError, setUploadError] = useState<string>('');
    const [isUploading, setIsUploading] = useState(false);

    const uploadResume = (event: ChangeEvent<HTMLInputElement>) => {
        console.log(event);
        const selectedFile = event.currentTarget.files?.[0] ?? null
        if (selectedFile) {
            const error = validateUploadFile(selectedFile, RESUME_FILE_POLICY)
            console.log("错误：" + error)
            if (error) {
                setUploadError(error)
                setFile(null)
                return;
            }
        }
        console.log(selectedFile);
        setFile(selectedFile)
        setUploadError('')
    }
    const upload = async () => {
        // const res = await axios.get('http://www.baidu.com')
        // if (res.status === 200) {
        //     setInterval(()=>console.log('waiting'), 1000);
        //     setPageState('SUCCESS')
        // } else {
        //     setPageState('FAIL')
        // }
        if (!file) {
            setUploadError('选有效文件')
            return;
        }
        setPageState('LOADING');
        setIsUploading(true);

        await new Promise((resolve) => {
            setTimeout(resolve, 3000);
        })
        setPageState('SUCCESS');
        setIsUploading(false);
    }


    return <main>F01 简历报告练习
        {pageState === 'SUCCESS' && <ResumeReport report={report}></ResumeReport>}
        {pageState === 'LOADING' && <p>加载中...</p>}
        {pageState === 'FAIL' && <p>加载失败</p>}
        <button onClick={() => setPageState('SUCCESS')}>点我成功</button>
        <br/>
        <button onClick={() => setPageState('FAIL')}>点我失败</button>
        <br/>
        <button onClick={() => setPageState('LOADING')}>点我加载</button>

        <br/>

        {/*<BatchUploadDropzone*/}
        {/*    entityLabel={'简历1'}*/}
        {/*    policy={RESUME_FILE_POLICY}*/}
        {/*    full={false}*/}
        {/*    notice={'测试99'*/}
        {/*    }*/}
        {/*    onFilesSelected={()=> console.log('你好')}*/}
        {/*/>*/}

        <input style={{backgroundColor: 'skyblue'}} type={"file"}
               onChange={uploadResume}/>
        <p>简历名称：{file?.name}</p>
        <p>上传错误：{uploadError}</p>

        <button disabled={isUploading} onClick={upload}>上传</button>

    </main>;
}
