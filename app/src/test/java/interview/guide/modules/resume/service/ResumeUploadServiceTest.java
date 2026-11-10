package interview.guide.modules.resume.service;

import interview.guide.common.config.AppConfigProperties;
import interview.guide.common.exception.BusinessException;
import interview.guide.common.exception.ErrorCode;
import interview.guide.common.transaction.TransactionalExecutor;
import interview.guide.infrastructure.file.FileStorageService;
import interview.guide.infrastructure.file.FileValidationService;
import interview.guide.modules.resume.listener.AnalyzeStreamProducer;
import interview.guide.modules.resume.repository.ResumeRepository;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("简历上传的失败补偿")
class ResumeUploadServiceTest {

  @Mock
  private ResumeParseService parseService;
  @Mock
  private FileStorageService storageService;
  @Mock
  private ResumePersistenceService persistenceService;
  @Mock
  private AnalyzeStreamProducer analyzeStreamProducer;
  @Mock
  private ResumeRepository resumeRepository;
  @Mock
  private TransactionalExecutor transactionalExecutor;

  private ResumeUploadService uploadService;

  @BeforeEach
  void setUp() {
    AppConfigProperties appConfig = new AppConfigProperties();
    appConfig.setAllowedTypes(List.of("text/plain"));
    uploadService = new ResumeUploadService(
        parseService, storageService, persistenceService, appConfig,
        new FileValidationService(), analyzeStreamProducer,
        resumeRepository, transactionalExecutor);
  }

  @Test
  @DisplayName("数据库保存失败时删除已上传文件并保留原异常")
  void deletesUploadedFileWhenDatabaseSaveFails() {
    // 准备输入和依赖行为，让调用能够走到数据库保存步骤。
    String resumeText = "虚构简历：测试用户，Java 后端开发。";
    MockMultipartFile file = new MockMultipartFile(
        "file", "resume.txt", "text/plain", resumeText.getBytes(StandardCharsets.UTF_8));
    String fileKey = "resumes/test-resume.txt";
    String fileUrl = "https://example.com/" + fileKey;
    BusinessException dbError = new BusinessException(
        ErrorCode.INTERNAL_ERROR, "模拟数据库保存失败");

    when(parseService.detectContentType(file)).thenReturn("text/plain");
    when(persistenceService.findExistingResume(file)).thenReturn(Optional.empty());
    when(parseService.parseResume(file)).thenReturn(resumeText);
    when(storageService.uploadResume(file)).thenReturn(fileKey);
    when(storageService.getFileUrl(fileKey)).thenReturn(fileUrl);
    when(persistenceService.saveResume(file, resumeText, fileKey, fileUrl))
        .thenThrow(dbError);

    // 执行真实上传编排，并验证向外抛出的仍是预设的数据库异常。
    assertThatThrownBy(() -> uploadService.uploadAndAnalyze(file))
        .isSameAs(dbError);

    // 验证补偿删除的对象正确，且流程没有继续发送分析任务。
    verify(storageService).deleteResume(fileKey);
    verifyNoInteractions(analyzeStreamProducer);
  }


  @Test
  @DisplayName("数据库保存失败，补偿删除也失败，最终仍抛出原来的 dbError")
  void deletesUploadedFileFailedWhenDatabaseSaveFails() {
    // 准备输入和依赖行为，让调用能够走到数据库保存步骤。
    String resumeText = "虚构简历：测试用户，Java 后端开发。";
    MockMultipartFile file = new MockMultipartFile(
            "file", "resume.txt", "text/plain", resumeText.getBytes(StandardCharsets.UTF_8));
    String fileKey = "resumes/test-resume.txt";
    String fileUrl = "https://example.com/" + fileKey;
    BusinessException dbError = new BusinessException(
            ErrorCode.INTERNAL_ERROR, "模拟数据库保存失败");

    when(parseService.detectContentType(file)).thenReturn("text/plain");
    when(persistenceService.findExistingResume(file)).thenReturn(Optional.empty());
    when(parseService.parseResume(file)).thenReturn(resumeText);
    when(storageService.uploadResume(file)).thenReturn(fileKey);
    when(storageService.getFileUrl(fileKey)).thenReturn(fileUrl);
    when(persistenceService.saveResume(file, resumeText, fileKey, fileUrl))
            .thenThrow(dbError);
    doThrow(new BusinessException(
            ErrorCode.INTERNAL_ERROR, "模拟文件删除失败")).when(storageService).deleteResume(fileKey);

    // 执行真实上传编排，并验证向外抛出的仍是预设的数据库异常。
    assertThatThrownBy(() -> uploadService.uploadAndAnalyze(file))
            .isSameAs(dbError);

    // 验证补偿删除的对象正确，且流程没有继续发送分析任务。
    verify(storageService).deleteResume(fileKey);
    verifyNoInteractions(analyzeStreamProducer);

  }
}
