import argparse
import torch
import os
from transformers import AutoTokenizer, AutoModelForCausalLM

def generate_text(model_path, prompt, length=100, temperature=0.7, top_p=0.9, top_k=50, repetition_penalty=1.2):
    """
    Generates text using a finetuned GPT-2 model.
    """
    if not os.path.exists(model_path):
        print(f"Error: Model path '{model_path}' does not exist.")
        return

    print(f"Loading model and tokenizer from {model_path}...")
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    
    # GPT-2 does not have a padding token by default
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
        
    model = AutoModelForCausalLM.from_pretrained(model_path)
    model.eval()

    # Device selection: CUDA, MPS (for Mac), or CPU
    if torch.cuda.is_available():
        device = torch.device("cuda")
    elif torch.backends.mps.is_available():
        device = torch.device("mps")
    else:
        device = torch.device("cpu")
    
    print(f"Using device: {device}")
    model.to(device)

    print(f"Generating starting from: \"{prompt}\"")
    
    inputs = tokenizer(prompt, return_tensors="pt").to(device)
    
    # Generate
    with torch.no_grad():
        output_tokens = model.generate(
            **inputs,
            max_length=len(inputs["input_ids"][0]) + length,
            do_sample=True,
            temperature=temperature,
            top_p=top_p,
            top_k=top_k,
            repetition_penalty=repetition_penalty,
            pad_token_id=tokenizer.pad_token_id,
            eos_token_id=tokenizer.eos_token_id,
            no_repeat_ngram_size=3
        )

    generated_text = tokenizer.decode(output_tokens[0], skip_special_tokens=True)
    
    print(f"\nFinal generated text:\n{generated_text}")
    return generated_text

def main():
    parser = argparse.ArgumentParser(description="Generate text using a finetuned GPT-2 model.")
    parser.add_argument("model_path", type=str, help="Path to the finetuned model directory")
    parser.add_argument("--prompt", type=str, default="Mr. Speaker, the government", help="Initial text to start generation")
    parser.add_argument("--length", type=int, default=100, help="Number of new tokens to generate")
    parser.add_argument("--temperature", type=float, default=0.7, help="Sampling temperature")
    parser.add_argument("--top_p", type=float, default=0.9, help="Top-p sampling threshold")
    parser.add_argument("--top_k", type=int, default=50, help="Top-k sampling threshold")
    parser.add_argument("--repetition_penalty", type=float, default=1.2, help="Repetition penalty")

    args = parser.parse_args()

    generate_text(
        args.model_path, 
        args.prompt, 
        args.length, 
        args.temperature, 
        args.top_p, 
        args.top_k, 
        args.repetition_penalty
    )

if __name__ == "__main__":
    main()
