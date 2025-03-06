import numpy as np
import dlib
import cv2
import hashlib
import os
import time
import traceback
from scipy.fftpack import dct, idct
from PIL import Image
import imagehash
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS

app = Flask(__name__)
CORS(app)  # CORS 활성화

# 필요한 디렉토리 생성
UPLOAD_FOLDER = './uploads'
PROCESSED_FOLDER = './processed'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(PROCESSED_FOLDER, exist_ok=True)

# 랜드마크 인덱스 정의
RIGHT_EYE = list(range(36, 42))
LEFT_EYE = list(range(42, 48))
NOSE = list(range(27, 36))
MOUTH = list(range(48, 68))

def apply_dct(img):
    return dct(dct(img.T, norm='ortho').T, norm='ortho')

def apply_idct(img):
    return idct(idct(img.T, norm='ortho').T, norm='ortho')

def generate_image_hash(file_path):
    hasher = hashlib.sha256()
    with open(file_path, 'rb') as f:
        while chunk := f.read(8192):
            hasher.update(chunk)
    return hasher.hexdigest()

def add_fake_landmark_signals(image, mask, fake_strength=50):
    fake_signal = np.zeros_like(image, dtype=np.float32)
    height, width = image.shape[:2]
    
    for _ in range(35):  # 가짜 랜드마크 35개 추가
        fake_x = np.random.randint(0, width)
        fake_y = np.random.randint(0, height)
        
        # 얼굴 영역과 겹치지 않도록 확인
        if fake_y < mask.shape[0] and fake_x < mask.shape[1] and mask[fake_y, fake_x] == 0:
            cv2.circle(fake_signal, (fake_x, fake_y), 1, (fake_strength, fake_strength, fake_strength), -1)
    
    return fake_signal

def safe_convert_image(image_path):
    """이미지를 안전하게 RGB 형식으로 변환"""
    try:
        pil_image = Image.open(image_path)
        
        # 이미지 모드 확인 및 RGB로 변환
        if pil_image.mode != 'RGB':
            print(f"이미지 모드 변환: {pil_image.mode} -> RGB")
            pil_image = pil_image.convert('RGB')
            
        # 변환된 이미지 저장
        converted_path = image_path + ".converted.jpg"
        pil_image.save(converted_path, 'JPEG', quality=95)
        print(f"변환된 이미지 저장 완료: {converted_path}")
        
        # 변환된 이미지 확인
        verify_image = Image.open(converted_path)
        print(f"변환된 이미지 검증: {verify_image.mode}, 크기: {verify_image.size}")
        
        return converted_path
    except Exception as e:
        print(f"이미지 변환 중 오류: {str(e)}")
        traceback.print_exc()
        return image_path  # 원본 경로 반환

def apply_ai_watermark(image, image_path, output_path):
    """AI 워터마크 적용 (얼굴 감지 없이도 작동)"""
    try:
        # 이미지 해시 계산
        image_hash = generate_image_hash(image_path)[:16]
        
        # DCT 적용
        dct_img = np.zeros_like(image, dtype=np.float32)
        for i in range(3):
            dct_img[:, :, i] = apply_dct(image[:, :, i].astype(np.float32))
        
        # 워터마크 생성
        height, width = image.shape[:2]
        watermark = np.zeros((height, width), dtype=np.float32)
        text_bits = [int(b) for b in ''.join(f'{ord(c):08b}' for c in image_hash)]
        
        # 표시 오프셋 및 강도
        offset = min(50, height//10, width//10)
        watermark_strength = 150
        
        # 워터마크 비트 배치
        for i, bit in enumerate(text_bits):
            x, y = divmod(i, width)
            if x + offset < height and y + offset < width:
                watermark[x + offset, y + offset] = bit * watermark_strength
        
        # 워터마크 적용
        watermarked_dct = dct_img + np.repeat(watermark[:, :, np.newaxis], 3, axis=2)
        
        # IDCT로 역변환
        watermarked_img = np.zeros_like(image, dtype=np.float32)
        for i in range(3):
            watermarked_img[:, :, i] = apply_idct(watermarked_dct[:, :, i])
        
        # 노이즈 추가
        dct_strength = 5
        noise_intensity = 2
        dct_pattern = np.random.normal(0, dct_strength, image.shape[:2])
        for i in range(3):
            watermarked_img[:, :, i] += dct_pattern
        
        noise = np.random.normal(0, noise_intensity, image.shape).astype(np.float32)
        final_img = np.clip(watermarked_img + noise, 0, 255).astype(np.uint8)
        
        # 텍스트 워터마크도 추가 (백업용)
        cv2.putText(final_img, "Security Mark", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 1)
        
        # 이미지 저장
        cv2.imwrite(output_path, final_img)
        print(f"AI 워터마크 적용 완료: {output_path}")
        return True
    except Exception as e:
        print(f"AI 워터마크 적용 중 오류: {str(e)}")
        traceback.print_exc()
        return False

def process_image(image_path, predictor_file, output_path):
    """이미지 처리 메인 함수"""
    if not os.path.exists(image_path):
        raise FileNotFoundError("이미지 파일이 존재하지 않습니다.")
    
    # 이미지 변환 (지원되는 형식으로)
    converted_path = safe_convert_image(image_path)
    
    try:
        # 이미지 로드
        image = cv2.imread(converted_path, cv2.IMREAD_COLOR)
        if image is None:
            print(f"OpenCV로 이미지를 읽을 수 없습니다. PIL로 변환 후 다시 시도합니다.")
            # 다시 PIL로 시도
            pil_image = Image.open(converted_path)
            rgb_image = pil_image.convert('RGB')
            # PIL 이미지를 NumPy 배열로 변환
            image = np.array(rgb_image)
            # BGR로 변환 (OpenCV 형식)
            image = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)
            
        if image is None or image.size == 0:
            raise ValueError("이미지를 로드할 수 없습니다.")
        
        # 얼굴 감지 시도
        try:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            detector = dlib.get_frontal_face_detector()
            predictor = dlib.shape_predictor(predictor_file)
            rects = detector(gray, 1)
            
            # 얼굴 영역 마스크 생성
            mask = np.zeros(image.shape[:2], dtype=np.uint8)
            
            if len(rects) > 0:
                print(f"{len(rects)}개의 얼굴 감지됨")
                # 얼굴 특징점 처리
                for rect in rects:
                    shape = predictor(gray, rect)
                    points = np.array([[p.x, p.y] for p in shape.parts()])
                    for feature in [RIGHT_EYE, LEFT_EYE, NOSE, MOUTH]:
                        cv2.fillPoly(mask, [points[feature].astype(np.int32)], 255)
                
                # 얼굴 영역에 노이즈 추가
                noise = np.random.normal(0, 0.08 * 255, image.shape).astype(np.float32)
                mask_3d = np.repeat(mask[:, :, np.newaxis], 3, axis=2) / 255.0
                processed_image = image.astype(np.float32) + noise * mask_3d
                
                # 가짜 랜드마크 추가
                fake_signal = add_fake_landmark_signals(processed_image, mask)
                processed_image += fake_signal  
                
                processed_image = np.clip(processed_image, 0, 255).astype(np.uint8)
            else:
                print("얼굴이 감지되지 않았습니다. 기본 이미지에 워터마크를 적용합니다.")
                processed_image = image
            
            # AI 워터마크 적용 (얼굴 여부와 상관없이)
            success = apply_ai_watermark(processed_image, converted_path, output_path)
            
            if not success:
                # AI 워터마크 실패 시 단순한 워터마크로 대체
                cv2.putText(processed_image, "Security Mark", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
                cv2.imwrite(output_path, processed_image)
            
        except Exception as face_error:
            print(f"얼굴 감지 오류: {str(face_error)}")
            traceback.print_exc()
            
            # 얼굴 감지 실패해도 AI 워터마크는 적용
            success = apply_ai_watermark(image, converted_path, output_path)
            
            if not success:
                # 단순 워터마크라도 적용
                cv2.putText(image, "Security Mark", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
                cv2.imwrite(output_path, image)
    
    except Exception as e:
        print(f"이미지 처리 중 오류: {str(e)}")
        traceback.print_exc()
        # 원본 이미지에 최소한의 워터마크 적용
        try:
            image = cv2.imread(image_path)
            if image is not None:
                cv2.putText(image, "Security Mark", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
                cv2.imwrite(output_path, image)
            else:
                # 마지막 수단: PIL로 시도
                pil_image = Image.open(image_path)
                pil_image.save(output_path)
        except:
            raise ValueError("이미지 처리에 완전히 실패했습니다.")
    
    finally:
        # 임시 파일 정리
        if converted_path != image_path and os.path.exists(converted_path):
            try:
                os.remove(converted_path)
            except:
                pass
    
    return output_path

@app.route("/")
def read_root():
    return jsonify({"message": "Flask 서버 실행 중"})

@app.route('/watermark', methods=['POST'])
def process_request():
    if 'image' not in request.files:
        return jsonify({"status": "error", "message": "이미지 파일이 없습니다"}), 400
    
    file = request.files['image']
    if file.filename == '':
        return jsonify({"status": "error", "message": "파일이 선택되지 않았습니다"}), 400
    
    # 파일 저장
    timestamp = int(time.time())
    filename = f"{timestamp}_{file.filename}"
    input_path = os.path.join(UPLOAD_FOLDER, filename)
    output_path = os.path.join(PROCESSED_FOLDER, f"watermarked_{filename}")
    
    file.save(input_path)
    print(f"이미지 저장됨: {input_path}")
    
    try:
        # 이미지 처리
        predictor_file = "C:\SecurityMark\SecurityMarkBackend\shape_predictor_68_face_landmarks.dat"
        process_image(input_path, predictor_file, output_path)
        
        # 처리된 이미지의 URL 반환
        server_url = request.host_url.rstrip('/')
        image_url = f"{server_url}/images/{os.path.basename(output_path)}"
        
        return jsonify({
            "status": "success", 
            "message": "이미지가 성공적으로 처리되었습니다",
            "watermarked_image_url": image_url
        })
    
    except Exception as e:
        print(f"처리 실패: {str(e)}")
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/images/<filename>', methods=['GET'])
def get_image(filename):
    """처리된 이미지를 클라이언트에게 제공하는 엔드포인트"""
    filepath = os.path.join(PROCESSED_FOLDER, filename)
    if os.path.exists(filepath):
        return send_file(filepath, mimetype='image/jpeg')
    else:
        return jsonify({"status": "error", "message": "파일을 찾을 수 없습니다"}), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)