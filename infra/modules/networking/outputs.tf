output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = [aws_subnet.pub_a.id, aws_subnet.pub_b.id]
}
