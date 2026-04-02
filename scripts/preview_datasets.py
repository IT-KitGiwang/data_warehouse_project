import os

def preview_datasets(dataset_path: str, num_lines: int = 5) -> None:
    """
    Duyệt qua tất cả các file trong thư mục dataset_path và in ra mục tiêu số dòng đầu tiên của mỗi file.
    """
    for root, _, files in os.walk(dataset_path):
        for file in files:
            file_path = os.path.join(root, file)
            print(f"{'='*50}")
            print(f"Previewing: {os.path.relpath(file_path, dataset_path)}")
            print(f"{'='*50}")
            try:
                # Đọc file với utf-8, nếu lỗi có thể bỏ qua hoặc thử encoding khác
                with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                    for i in range(num_lines):
                        line = f.readline()
                        if not line:
                            break
                        print(line.strip())
            except Exception as e:
                 print(f"Lỗi khi đọc file {file_path}: {e}")
            print("\n")

if __name__ == "__main__":
    # Xác định đường dẫn tương đối tới thư mục 'datasets'
    current_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(current_dir)
    dataset_dir = os.path.join(project_root, 'datasets')
    
    if os.path.exists(dataset_dir):
        preview_datasets(dataset_dir, num_lines=5)
    else:
        print(f"Error: Không tìm thấy thư mục {dataset_dir}")
