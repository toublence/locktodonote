# Xcode 패키지 연결 복구 · 2026-10-31

- 증상: 앱/위젯의 LockTodoNoteShared 및 Firebase·Google Ads·UMP·Meta·FBAudienceNetwork가 Missing package product로 표시됨.
- 확인: 로컬 패키지와 프로젝트 참조는 존재했고, 저장 공간 확보 후 약 12GB의 여유 공간을 확인함. 프로젝트 소스/상품 이름 오류는 발견하지 않음. 앞선 공간 소진 이후의 캐시 상태가 원인일 가능성이 있으나 단정하지 않음.
- 조치: Xcode 기본 DerivedData에서 Package.resolved의 버전만 사용해 패키지를 다시 해석. Xcode Resolve Package Versions, 프로젝트 다시 열기, 해당 프로젝트 Clean Build Folder로 이전 빌드 오류를 정리함.
- 결과: xcodebuild -resolvePackageDependencies 종료 코드 0. LockTodoNoteShared를 포함한 전체 패키지 해석 성공. Xcode Issue Navigator에서 8개 Missing package product 오류가 사라짐.
- 기존 패키지 버전/Package.resolved/project.pbxproj와 앱 기능 코드는 변경하지 않음. 장시간 전체 빌드는 실행하지 않음.

해석 명령:

```sh
xcodebuild -resolvePackageDependencies -project LockTodoNote.xcodeproj -scheme LockTodoNote -onlyUsePackageVersionsFromResolvedFile
```

실행 로그: `/tmp/locktodonote-package-recovery-20261031.log`

## 재발 후 재조사

13:47 빌드 오류 발생 후 확인한 Xcode 기본 DerivedData에는 SourcePackages 디렉터리 자체가 없었다. 앞선 복구 때 존재했던 외부 패키지 캐시가 다시 없어졌으며, 누가/어떤 정리 도구가 삭제했는지는 확인하지 않았다. 로컬 LockTodoNoteShared는 남아 이번에는 외부 제품 6개만 누락됐다. 저장 공간은 약 32GB였다.

프로젝트를 닫고 /tmp의 정상 캐시를 APFS clone으로 기본 SourcePackages 경로에 복구했다. 복원한 workspace-state의 artifact 절대 경로도 실제 복원 경로로 맞췄다. 앱 코드/프로젝트 제품 이름/고정 버전은 변경하지 않았다. Xcode에서 프로젝트를 다시 열고 Resolve Package Versions를 실행했다.

빌드 준비 검증 로그 `/tmp/locktodonote-package-build-graph-20261031.log`에서 71개 타깃 의존성 그래프와 문제의 외부 제품 6개를 모두 확인했다. Missing package product는 발생하지 않았다. 다만 -dry-run은 현재 new build system에서 미지원으로 명령 전체는 exit 65로 끝났다. 따라서 전체 컴파일/링크 성공으로 표시하지 않는다.

Xcode가 실행 중일 때 이 프로젝트의 SourcePackages를 삭제하면 IDE의 메모리 상태와 디스크 캐시가 달라져 다시 발생할 수 있다. 공간 정리 후에는 프로젝트를 다시 열고 패키지를 해석해야 한다. 이 폴더는 외부 패키지를 사용하는 빌드에 필요하다.
