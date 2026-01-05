#!/usr/bin/env python3
"""
下载Qwen2.5-7B-Instruct-GPTQ-Int4模型
"""
import os
from huggingface_hub import snapshot_download

repo_id = "Qwen/Qwen2.5-7B-Instruct-GPTQ-Int4"
model_dir = "/dss/dsshome1/0F/ra29bux3/AlignSurvey/models/Qwen2.5-7B-Instruct-GPTQ-Int4"

print("=" * 70)
print(f"下载模型: {repo_id}")
print(f"保存位置: {model_dir}")
print("=" * 70)

os.makedirs(model_dir, exist_ok=True)

try:
    print("\n开始下载模型...")
    print("注意: GPTQ量化模型约2-3GB，下载可能需要一些时间...\n")
    
    snapshot_download(
        repo_id=repo_id,
        local_dir=model_dir,
        local_dir_use_symlinks=False,
        resume_download=True,
    )
    
    print("\n" + "=" * 70)
    print("✓ 模型下载完成！")
    print(f"模型保存在: {model_dir}")
    print("=" * 70)
    
except Exception as e:
    print(f"\n✗ 下载失败: {e}")
    import traceback
    traceback.print_exc()

