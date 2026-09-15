# FPGA-VGA-PhotoBooth-Project

**FPGA 기반 실시간 영상 처리 및 편집 — 4컷 포토부스 시스템**

---

## 프로젝트 개요

- FPGA(Basys3) 기반으로 동작하는 **셀프 네컷사진 부스**
- **카메라로 촬영**한 사진을 보드 위에서 **실시간으로 편집**
- 완성된 사진을 **UART로 PC에 전송**해 **QR코드로 다운로드**할 수 있게 만든 시스템

## 프로젝트 목표

- FPGA로 완결된 임베디드 시스템 구현
- 실시간 영상처리 파이프라인 설계 및 검증
- 하드웨어-소프트웨어 통합
- 협업 기반 대규모 모듈 설계 경험

## 배운점
1. VGA 영상처리 방법: 픽셀 클록에 맞춰 매 클럭 좌표를 처리하는 실시간 영상처리 파이프라인의 동작 원리를 익힘
2. 명세서의 중요성: 기획 단계에서 서로 의견을 나누며 구조와 신호를 명확히 정의하는 것의 중요성을 깨달았다
3. 메모리 절감 설계: 제한된 BRAM 자원 안에서 포트 구조를 최적화(3포트→2포트)하는 메모리 설계 경험
4. 타이밍 최적화: 파이프라인 구조를 통해 Negative Slack(타이밍 위반)을 해결하는 방법을 익힘

## System Flow

1. Opening
2. Filter Select
3. Photo Capture
4. Frame Select
5. Sticker Mode
6. Draw / Color Picker Mode
7. Final Photo + QR

## System Block Diagram

- 버튼·스위치 입력을 동기화하여 System Controller로 전달, 시스템 상태에 따라 각 모듈 제어
- OV7670의 픽셀 데이터를 Camera Interface로 수신 → Down Scaler, Filter를 거쳐 편집용 이미지로 저장
- Marker 좌표 기반 편집 결과를 VGA Monitor에 실시간 출력, UART로 Python UI에 전송

## 모듈 구성

| 모듈 | 설명 |
|---|---|
| System Controller | 버튼/스위치 입력 및 각 상태(촬영/필터/스티커/전송) 관리하는 FSM |
| Camera Interface & Marker Detector | OV7670 SCCB 초기설정 및 영상 스트림 수신, 마커(펜/커서) 위치 인식 |
| Capture & Filter | Down Scaler(다운스케일), Filter(흑백/세피아/소프트포커스/필름룩), Capture(프레임 메모리 저장) |
| **Edit Engine** | Memory, VGA Controller, Marker Overlay, Memory Writer(Sticker/Drawing/Color Picker), Sticker ROM, Image Export |
| UART | 편집 완료 이미지를 Status Data + RGB444 Pixel 프레임으로 PC에 전송 |
| PC (Python UI) — FOUR CUT STUDIO | 촬영 가이드, 필터·프레임·스티커 선택 UI, 최종 이미지 저장, QR코드 생성 |

> **본인 담당: Edit Engine, VGA Controller, SCCB Controller**

### Filter 종류

- 흑백 (Y = 0.299R + 0.587G + 0.114B)
- 세피아
- 소프트포커스 (3x3 가우시안 블러 합성)
- 필름룩 (채널별 게인 조정)

### UART 전송 포맷

- Status Data (32bit) + RGB444 Pixel (12bit)를 8bit 단위로 분할해 LSB First로 전송
- Baud Generator로 1Mbps 타이밍 생성

### 본인 담당 모듈 상세

- **Edit Engine**: Marker Overlay(화면 좌표-마커 비교 후 오버레이 색상/원본 선택), Memory Writer(스티커·드로잉·컬러피커 확정 write), Image Export(완성 이미지를 UART로 픽셀 단위 스트리밍)
- **VGA Controller**: 640×480 해상도 기준 h_sync/v_sync 및 픽셀 좌표(x_pixel, y_pixel) 타이밍 생성
- **SCCB Controller**: OV7670 카메라 센서 레지스터 초기 설정을 위한 SCCB(I2C 유사) 통신 제어

## Trouble Shooting

**문제**: 화면 좌표를 메모리 주소로 변환하는 곱셈 계산 경로에서 Negative Slack 발생

- Vivado Timing Analysis 결과 **WNS -5.156ns**, TNS -2616.955ns, Failing Endpoint 648개 확인
- `mem_addr_gen`의 VGA 픽셀 주소, `mem_writer`의 Sticker·Color Picker Write 주소 계산 경로가 주요 Critical Path
- 원인: 좌표 변환과 곱셈·덧셈 연산이 한 사이클에 수행되면서 조합 논리 경로 지연 증가

**해결**: 파이프라인 레지스터 삽입

1. 다운스케일 적용된 x_pixel, y_pixel을 레지스터에 저장
2. 저장된 좌표로 주소 계산(곱셈)을 수행한 후, 그 결과를 다시 출력 레지스터에 저장

**결과**: 주소 계산 경로 분리를 통해 조합 논리 지연 감소

| | Before | After |
|---|---|---|
| WNS | -5.156 ns | **+0.463 ns** |
| TNS | -2616.955 ns | 0.000 ns |
| Failing Endpoints | 648 | **0** |

→ Timing Constraint 충족

## 결론

- OV7670 영상 데이터를 FPGA에서 실시간으로 처리하여 사진 촬영, 필터 적용, Sticker·Drawing·Color Picker 편집 및 VGA 출력을 구현함
- 최종 편집 이미지를 UART로 Python UI에 전송해 저장·QR코드 생성까지 연동하고, 주소 계산 경로의 파이프라인화를 통해 Timing Constraint를 충족함

## 기술 스택

| 구분 | 사용 기술 |
|---|---|
| 보드 | Digilent Basys3 |
| 카메라 | OV7670 |
| HDL | SystemVerilog |
| 개발 툴 | Vivado |
| PC 프로그램 | Python (FOUR CUT STUDIO — 촬영 가이드, 필터/스티커 선택, QR코드 생성) |
